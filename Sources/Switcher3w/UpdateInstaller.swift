// Compiled out of the App Store flavour alongside UpdateChecker — see that file.
#if !SWITCHER_APPSTORE
import AppKit
import CryptoKit
import Security

/// Verified in-place update: download DMG → SHA-256 against the published manifest →
/// mount → code-signature identity must equal the running app's (this is what keeps
/// TCC permissions across updates — same stable cert) → move-aside + ditto swap with
/// rollback → relaunch via AppRelauncher.
enum UpdateInstaller {

    static func install(_ info: UpdateInfo) async throws {
        // 1. Expected checksum: version.json release asset, else the release-body fallback.
        let expected = try await expectedSHA256(info)

        // 2. Download the DMG. URLSession downloads from this app carry no quarantine
        //    attribute (no LSFileQuarantineEnabled) — strip defensively anyway.
        let (tmp, _) = try await URLSession.shared.download(from: info.dmgURL)
        let dmg = tmp.deletingLastPathComponent().appendingPathComponent("Switcher3way-update-\(info.version).dmg")
        try? FileManager.default.removeItem(at: dmg)
        try FileManager.default.moveItem(at: tmp, to: dmg)
        defer { try? FileManager.default.removeItem(at: dmg) }
        stripQuarantine(dmg.path, recursive: false)

        // 3. Checksum gate.
        let actual = try sha256(of: dmg)
        guard actual == expected else {
            rslog("update: sha256 mismatch — expected \(expected), got \(actual)")
            throw UpdateError.checksumMismatch
        }

        // 4. Mount read-only, find the bundle.
        let mountPoint = try mount(dmg)
        defer { detach(mountPoint) }
        let newBundle = URL(fileURLWithPath: mountPoint).appendingPathComponent("Switcher3way.app")
        guard FileManager.default.fileExists(atPath: newBundle.path) else { throw UpdateError.bundleNotFound }

        // 5. Signature gate: valid signature AND the same certificate as the running app.
        try verifySignatureMatchesRunningApp(newBundle)

        // 6. Swap in place: move the running bundle aside, ditto the new one in,
        //    roll the old one back if anything fails after the move.
        let installed = URL(fileURLWithPath: Bundle.main.bundlePath)
        let aside = installed.deletingLastPathComponent()
            .appendingPathComponent(".Switcher3way.old.\(ProcessInfo.processInfo.processIdentifier)")
        try? FileManager.default.removeItem(at: aside)
        try FileManager.default.moveItem(at: installed, to: aside)
        do {
            try run("/usr/bin/ditto", [newBundle.path, installed.path])
        } catch {
            try? FileManager.default.removeItem(at: installed)
            try? FileManager.default.moveItem(at: aside, to: installed)   // rollback → working install
            throw UpdateError.copyFailed(error.localizedDescription)
        }
        stripQuarantine(installed.path, recursive: true)
        try? FileManager.default.removeItem(at: aside)

        rslog("update: installed \(info.version) at \(installed.path), relaunching")
        await MainActor.run {
            AppRelauncher.relaunch(bundlePath: installed.path)
        }
    }

    // MARK: - Checksum

    private static func expectedSHA256(_ info: UpdateInfo) async throws -> String {
        if let manifestURL = info.manifestURL {
            let (data, _) = try await URLSession.shared.data(from: manifestURL)
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let sha = obj["sha256"] as? String, sha.count == 64 {
                return sha.lowercased()
            }
            rslog("update: manifest asset present but unreadable — falling back to release notes")
        }
        if let sha = info.notesSHA256 { return sha }
        throw UpdateError.noChecksum
    }

    private static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Code signature

    /// The new bundle must be signed by us. Two ways to be us, tried in that order:
    ///
    /// 1. **Developer ID, Apple-anchored, our team** — the shipping case. Checked with a
    ///    code requirement (`anchor apple generic` + leaf OU), NOT by comparing certificate
    ///    bytes: a Developer ID certificate expires and is re-issued with a different leaf,
    ///    and a byte comparison would silently break every installed copy's updater on the
    ///    day that happens. The team identifier survives re-issue; the Apple anchor is what
    ///    makes it unforgeable (a self-signed certificate can put any string in its OU, and
    ///    `SecStaticCodeCheckValidity` alone would accept it).
    ///
    /// 2. **Byte-identical leaf certificate** — the legacy path, for the self-signed identity
    ///    the fork shipped with before it had an Apple Developer account. Kept so that a
    ///    self-signed build can still update to another self-signed build.
    ///
    /// The combination is what carries existing installs across the migration: a self-signed
    /// build fails (2) against a Developer ID successor but passes (1), because the team it
    /// should trust is stamped into its own signed Info.plist as `RSReleaseTeamID`.
    ///
    /// Ad-hoc builds have no certificate at all → they can neither ship nor accept updates.
    private static func verifySignatureMatchesRunningApp(_ bundle: URL) throws {
        if let team = releaseTeamIdentifier, signedByDeveloperID(bundle, team: team) {
            rslog("update: signature OK — Developer ID team \(team)")
            return
        }
        guard let newCert = validLeafCertificate(at: bundle) else { throw UpdateError.signatureInvalid }
        guard let ourCert = validLeafCertificate(at: URL(fileURLWithPath: Bundle.main.bundlePath)) else {
            throw UpdateError.signatureInvalid
        }
        guard newCert == ourCert else {
            rslog("update: signature rejected — not our Developer ID team and leaf differs")
            throw UpdateError.signatureMismatch
        }
        rslog("update: signature OK — identical leaf certificate (legacy identity)")
    }

    /// The Developer ID team whose builds this copy accepts, stamped at build time by
    /// `build_app.sh` from `signing/developer-id.conf`. Inside our own signed bundle, so
    /// it cannot be edited without invalidating the running app's signature. `nil` when
    /// the app was built without a configured team (development builds).
    private static var releaseTeamIdentifier: String? {
        guard let team = Bundle.main.object(forInfoDictionaryKey: "RSReleaseTeamID") as? String,
              !team.isEmpty else { return nil }
        return team
    }

    /// Does the bundle carry a valid Developer ID signature issued to `team` by Apple?
    private static func signedByDeveloperID(_ bundle: URL, team: String) -> Bool {
        // Reject anything that could break out of the requirement string. Team IDs are
        // 10 alphanumerics; nothing else has any business reaching SecRequirement.
        guard team.count == 10, team.allSatisfy({ $0.isLetter || $0.isNumber }) else { return false }
        let text = "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess,
              let requirement else { return false }
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundle as CFURL, [], &staticCode) == errSecSuccess,
              let code = staticCode else { return false }
        return SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess
    }

    /// Validates the static code at `url` and returns its leaf certificate DER bytes.
    private static func validLeafCertificate(at url: URL) -> Data? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let code = staticCode,
              SecStaticCodeCheckValidity(code, [], nil) == errSecSuccess else { return nil }
        var infoRef: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &infoRef) == errSecSuccess,
              let dict = infoRef as? [String: Any],
              let certs = dict[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let leaf = certs.first else { return nil }
        return SecCertificateCopyData(leaf) as Data
    }

    // MARK: - DMG handling

    private static func mount(_ dmg: URL) throws -> String {
        let output = try run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-plist"])
        guard let data = output.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]],
              let mountPoint = entities.compactMap({ $0["mount-point"] as? String }).first else {
            throw UpdateError.mountFailed
        }
        return mountPoint
    }

    private static func detach(_ mountPoint: String) {
        _ = try? run("/usr/bin/hdiutil", ["detach", mountPoint, "-quiet"])
    }

    // MARK: - Tools

    private static func stripQuarantine(_ path: String, recursive: Bool) {
        var args = ["-d"]
        if recursive { args = ["-dr"] }
        args += ["com.apple.quarantine", path]
        _ = try? run("/usr/bin/xattr", args)   // absent attribute → non-zero exit, ignored
    }

    @discardableResult
    private static func run(_ tool: String, _ args: [String]) throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: tool)
        task.arguments = args
        let out = Pipe(), err = Pipe()
        task.standardOutput = out
        task.standardError = err
        try task.run()
        task.waitUntilExit()
        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard task.terminationStatus == 0 else {
            let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(domain: "UpdateInstaller", code: Int(task.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "\(tool) failed: \(stderr.prefix(200))"])
        }
        return stdout
    }
}

#endif  // !SWITCHER_APPSTORE

import AppKit

/// A discovered release worth offering to the user.
struct UpdateInfo {
    let version: String          // "1.1.0" (tag without the leading "v")
    let notes: String            // release body (markdown, shown truncated in the alert)
    let dmgURL: URL
    let manifestURL: URL?        // version.json release asset — checksum source of truth
    let notesSHA256: String?     // fallback: checksum parsed from the release body (pre-manifest releases)
}

enum UpdateError: LocalizedError {
    case badResponse(Int)
    case noArtifact
    case noChecksum
    case checksumMismatch
    case bundleNotFound
    case signatureInvalid
    case signatureMismatch
    case mountFailed
    case copyFailed(String)

    var errorDescription: String? {
        switch self {
        case .badResponse(let code): return "Release query failed (HTTP \(code))."
        case .noArtifact: return "The latest release has no DMG asset."
        case .noChecksum: return "No published checksum to verify the download against."
        case .checksumMismatch: return "The downloaded file failed checksum verification."
        case .bundleNotFound: return "The update image does not contain Switcher3way.app."
        case .signatureInvalid: return "The downloaded app's code signature is invalid."
        case .signatureMismatch: return "The downloaded app is signed with a different identity."
        case .mountFailed: return "Could not open the downloaded disk image."
        case .copyFailed(let why): return "Could not install the new version: \(why)"
        }
    }
}

/// Checks the fork's OWN public releases repo for new versions and drives the
/// notify → one-click-install flow. The upstream updater was deleted at fork time;
/// this one can never offer a stock rashn/RuSwitcher build because its only source
/// is WhisKeySwitch/switcher3way-releases.
@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()

    /// Public downloads repo — the only update source.
    nonisolated private static let api = URL(string: "https://api.github.com/repos/WhisKeySwitch/switcher3way-releases/releases/latest")!
    private static let checkInterval: TimeInterval = 24 * 60 * 60

    private var isChecking = false { didSet { onStateChange?() } }
    private(set) var isInstalling = false { didSet { onStateChange?() } }
    /// True while a check or install runs — the menu item shows a disabled busy title.
    var isBusy: Bool { isChecking || isInstalling }
    /// Called on busy-state changes so AppDelegate can rebuild the menu.
    var onStateChange: (() -> Void)?

    private var timer: Timer?

    // MARK: - Scheduling

    /// (Re)starts the automatic schedule per the setting: first check ~15 s after launch
    /// (don't compete with startup/permission flows), then daily. Stops the timer when
    /// the setting is off; the manual menu check keeps working regardless.
    func startSchedule() {
        timer?.invalidate(); timer = nil
        guard SettingsManager.shared.checkForUpdates else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self, SettingsManager.shared.checkForUpdates else { return }
            self.check(interactive: false)
        }
        timer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { _ in
            Task { @MainActor in
                guard SettingsManager.shared.checkForUpdates else { return }
                UpdateChecker.shared.check(interactive: false)
            }
        }
    }

    /// Menu-initiated check: reports every outcome (update / up-to-date / error)
    /// and ignores a previously skipped version.
    func checkManually() { check(interactive: true) }

    // MARK: - Check

    private func check(interactive: Bool) {
        guard !isBusy else { return }
        isChecking = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.isChecking = false }
            do {
                let info = try await Self.fetchLatest()
                SettingsManager.shared.lastUpdateCheck = Date()
                let current = Self.currentVersion()
                guard Self.isNewer(info.version, than: current) else {
                    rslog("update: up to date (current \(current), latest \(info.version))")
                    if interactive { Self.showUpToDate(current) }
                    return
                }
                if !interactive, SettingsManager.shared.skippedVersion == info.version {
                    rslog("update: \(info.version) available but skipped by user")
                    return
                }
                rslog("update: \(info.version) available (current \(current))")
                self.offer(info)
            } catch {
                // Background checks fail silently (offline, rate limit) — log and retry next cycle.
                rslog("update: check failed — \(error.localizedDescription)")
                if interactive { Self.showError(L10n.updateCheckFailedTitle, error) }
            }
        }
    }

    // MARK: - Offer & install

    /// The single update alert: Install and Relaunch / Later / Skip This Version.
    private func offer(_ info: UpdateInfo) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L10n.updateAvailableTitle(info.version)
        var body = L10n.updateInstalledVersion(Self.currentVersion())
        let notes = info.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty { body += "\n\n" + String(notes.prefix(700)) }
        alert.informativeText = body
        alert.addButton(withTitle: L10n.updateInstall)
        alert.addButton(withTitle: L10n.updateLater)
        alert.addButton(withTitle: L10n.updateSkip)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            install(info)
        case .alertThirdButtonReturn:
            SettingsManager.shared.skippedVersion = info.version
            rslog("update: user skipped \(info.version)")
        default:
            break // Later — offered again on the next check
        }
    }

    private func install(_ info: UpdateInfo) {
        guard !isInstalling else { return }
        isInstalling = true
        Task { [weak self] in
            guard let self else { return }
            do {
                try await UpdateInstaller.install(info)
                // On success the installer relaunches the app; execution rarely returns here.
            } catch {
                rslog("update: install failed — \(error.localizedDescription)")
                Self.showError(L10n.updateInstallFailedTitle, error)
            }
            self.isInstalling = false
        }
    }

    // MARK: - Version helpers

    nonisolated static func currentVersion() -> String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }

    /// Numeric segment-wise semver compare ("1.10.0" > "1.9.9"; missing segments are 0).
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
                .split(separator: ".")
                .map { Int($0.prefix(while: { $0.isNumber })) ?? 0 }
        }
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: - GitHub API

    private struct APIRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
        }
        let tag_name: String
        let body: String?
        let assets: [Asset]
    }

    nonisolated private static func fetchLatest() async throws -> UpdateInfo {
        var req = URLRequest(url: api)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.badResponse((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let rel = try JSONDecoder().decode(APIRelease.self, from: data)
        let version = rel.tag_name.hasPrefix("v") ? String(rel.tag_name.dropFirst()) : rel.tag_name
        guard let dmgAsset = rel.assets.first(where: { $0.name.hasSuffix(".dmg") }),
              let dmgURL = URL(string: dmgAsset.browser_download_url) else {
            throw UpdateError.noArtifact
        }
        let manifestURL = rel.assets.first(where: { $0.name == "version.json" })
            .flatMap { URL(string: $0.browser_download_url) }
        return UpdateInfo(version: version,
                          notes: rel.body ?? "",
                          dmgURL: dmgURL,
                          manifestURL: manifestURL,
                          notesSHA256: parseSHA256(from: rel.body ?? ""))
    }

    /// First 64-hex-char run in the release body — checksum fallback for releases
    /// published before the version.json manifest asset was introduced.
    nonisolated static func parseSHA256(from body: String) -> String? {
        guard let range = body.range(of: "[0-9a-fA-F]{64}", options: .regularExpression) else { return nil }
        return String(body[range]).lowercased()
    }

    // MARK: - Result alerts (manual checks only)

    private static func showUpToDate(_ current: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L10n.updateUpToDateTitle
        alert.informativeText = L10n.updateUpToDateText(current)
        alert.runModal()
    }

    private static func showError(_ title: String, _ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}

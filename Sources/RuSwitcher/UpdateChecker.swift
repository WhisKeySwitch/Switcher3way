import AppKit
import Foundation

/// Проверяет наличие обновлений через GitHub
@MainActor
enum UpdateChecker {
    // URL к JSON с информацией о версии (заменить на реальный)
    private static let versionURL = "https://raw.githubusercontent.com/rashn/RuSwitcher/main/version.json"

    /// Структура JSON версии
    private struct VersionInfo: Decodable {
        let version: String
        let url: String
        let notes: String?
        let sha256: String?
    }

    /// Проверить при запуске (с задержкой 5 сек, не чаще раза в сутки).
    /// Отключается через настройку `checkUpdatesEnabled`. Ручная проверка (`checkNow`) работает всегда.
    static func checkOnLaunch() {
        guard shouldAutoCheck() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            Task { await check(silent: true) }
        }
    }

    /// Периодическая тихая авто-проверка, пока приложение работает (из таймера AppDelegate).
    /// Тот же троттл (не чаще раза в сутки) и та же настройка `checkUpdatesEnabled`, что и на старте,
    /// поэтому долго-живущий инстанс тоже ловит новые версии, а не только при перезапуске.
    static func checkPeriodic() {
        guard shouldAutoCheck() else { return }
        Task { await check(silent: true) }
    }

    /// Можно ли сейчас авто-проверять: включено в настройках И прошло ≥24ч с последней проверки.
    private static func shouldAutoCheck() -> Bool {
        let settings = SettingsManager.shared
        guard settings.checkUpdatesEnabled else { return false }
        if let lastCheck = settings.lastUpdateCheck,
           Date().timeIntervalSince(lastCheck) < 86400 {
            return false // Проверяли менее суток назад
        }
        return true
    }

    /// Проверить вручную (всегда показывает результат)
    static func checkNow() {
        Task { await check(silent: false) }
    }

    private static func check(silent: Bool) async {
        // ── ОТКЛЮЧЕНО в форке Switcher3way ──────────────────────────────────────
        // Апстрим (rashn/RuSwitcher) — сток 2-way версия; авто-апдейт оттуда затёр бы
        // нашу кастомную 3-way сборку. Сеть не трогаем; авто-проверки молчат, ручная
        // проверка просто подтверждает «актуально». Вернуть апдейты — убрать этот блок.
        rslog("UpdateChecker: disabled in Switcher3way fork")
        if !silent { await showUpToDateAlert() }
        return

        guard let url = URL(string: versionURL) else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let info = try JSONDecoder().decode(VersionInfo.self, from: data)

            SettingsManager.shared.lastUpdateCheck = Date()

            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

            if compareVersions(info.version, isNewerThan: currentVersion) {
                if SettingsManager.shared.skippedVersion == info.version && silent {
                    return // Пользователь пропустил эту версию
                }
                await showUpdateAlert(info: info)
            } else if !silent {
                await showUpToDateAlert()
            }
        } catch {
            rslog("UpdateChecker error: \(error)")
            if !silent {
                await showErrorAlert()
            }
        }
    }

    private static func showUpdateAlert(info: VersionInfo) async {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.updateAvailable
        alert.informativeText = "\(L10n.updateNewVersion) \(info.version)\n\(info.notes ?? "")"
        alert.addButton(withTitle: L10n.updateInstallRestart)  // 1st
        alert.addButton(withTitle: L10n.updateDownload)         // 2nd
        alert.addButton(withTitle: L10n.updateSkip)             // 3rd
        alert.addButton(withTitle: L10n.updateLater)            // 4th

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            await installAndRestart(info: info)
        case .alertSecondButtonReturn:
            if let url = URL(string: info.url) {
                NSWorkspace.shared.open(url)
            }
        case .alertThirdButtonReturn:
            SettingsManager.shared.skippedVersion = info.version
        default:
            break
        }
    }

    // MARK: - Install & Restart

    private static func installAndRestart(info: VersionInfo) async {
        let version = info.version

        // 0. Версия приходит из сети — не доверяем вслепую (попадёт в URL и в сравнение).
        guard version.range(of: "^[0-9]+(\\.[0-9]+){1,3}$", options: .regularExpression) != nil else {
            rslog("Update: rejected malformed version '\(version)'")
            await showInstallError(L10n.updateVerifyFailed)
            return
        }

        // 0a. sha256 обязателен для установки на месте: молча подменять приложение
        //     keylogger-класса без проверки нельзя. Нет хэша — откат на загрузку
        //     в браузере, где работает Gatekeeper/нотаризация.
        guard let expectedSHA = info.sha256, !expectedSHA.isEmpty else {
            rslog("Update: no sha256 in version.json — falling back to browser download")
            if let url = URL(string: info.url) { NSWorkspace.shared.open(url) }
            return
        }

        guard let dmgURL = URL(string: SettingsManager.releaseDMGURL(version: version)) else {
            await showInstallError(L10n.updateDownloadFailed)
            return
        }

        let tmpPath = "/tmp/RuSwitcher-update.dmg"
        let tmpURL = URL(fileURLWithPath: tmpPath)

        // 1. Скачать
        rslog("Update: downloading \(dmgURL)")
        do {
            let (data, response) = try await URLSession.shared.data(from: dmgURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                await showInstallError(L10n.updateDownloadFailed)
                return
            }
            try data.write(to: tmpURL)
        } catch {
            rslog("Update: download failed — \(error)")
            await showInstallError(L10n.updateDownloadFailed)
            return
        }

        // 2. Проверить sha256 (обязательно)
        let actualSHA = sha256OfFile(at: tmpPath)
        guard actualSHA == expectedSHA else {
            rslog("Update: sha256 mismatch expected=\(expectedSHA) actual=\(actualSHA ?? "nil")")
            try? FileManager.default.removeItem(at: tmpURL)
            await showInstallError(L10n.updateVerifyFailed)
            return
        }
        rslog("Update: sha256 verified")

        // 3. Смонтировать DMG
        let mountPoint = "/tmp/RuSwitcher-update-mount"
        let mount = Process()
        mount.launchPath = "/usr/bin/hdiutil"
        mount.arguments = ["attach", tmpPath, "-nobrowse", "-readonly", "-mountpoint", mountPoint]
        mount.standardOutput = FileHandle.nullDevice
        mount.standardError = FileHandle.nullDevice
        do {
            try mount.run()
            mount.waitUntilExit()
            guard mount.terminationStatus == 0 else {
                rslog("Update: hdiutil attach failed with status \(mount.terminationStatus)")
                await showInstallError(L10n.updateInstallFailed)
                return
            }
        } catch {
            rslog("Update: hdiutil attach error — \(error)")
            await showInstallError(L10n.updateInstallFailed)
            return
        }

        defer {
            // Размонтировать и почистить
            let detach = Process()
            detach.launchPath = "/usr/bin/hdiutil"
            detach.arguments = ["detach", mountPoint, "-quiet"]
            detach.standardOutput = FileHandle.nullDevice
            detach.standardError = FileHandle.nullDevice
            try? detach.run()
            detach.waitUntilExit()
            try? FileManager.default.removeItem(at: tmpURL)
        }

        // 4. Найти .app в смонтированном томе
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: mountPoint),
              let appName = contents.first(where: { $0.hasSuffix(".app") }) else {
            rslog("Update: no .app found in mounted DMG")
            await showInstallError(L10n.updateInstallFailed)
            return
        }

        let sourceApp = URL(fileURLWithPath: mountPoint).appendingPathComponent(appName)
        let currentApp = URL(fileURLWithPath: Bundle.main.bundlePath)

        // 5. ПРОВЕРКА ПОДПИСИ: единственная реальная защита от подмены кода.
        //    sha256 защищает лишь от битой загрузки — если подменить и DMG, и хэш,
        //    спасает только пиннинг Developer ID нашей команды.
        guard verifyNotarizedSignature(at: sourceApp.path) else {
            rslog("Update: signature/notarization check FAILED — aborting")
            await showInstallError(L10n.updateVerifyFailed)
            return
        }

        // 5a. Идентичность бандла: тот же bundle id и версия совпадает с заявленной.
        let mountedInfo = Bundle(url: sourceApp)?.infoDictionary
        let mountedID = mountedInfo?["CFBundleIdentifier"] as? String
        let mountedVersion = mountedInfo?["CFBundleShortVersionString"] as? String
        guard mountedID == Bundle.main.bundleIdentifier else {
            rslog("Update: bundle id mismatch (\(mountedID ?? "nil"))")
            await showInstallError(L10n.updateVerifyFailed)
            return
        }
        guard mountedVersion == version else {
            rslog("Update: bundle version mismatch — announced \(version), contains \(mountedVersion ?? "nil")")
            await showInstallError(L10n.updateVerifyFailed)
            return
        }

        // 6. Скопировать .app с read-only тома DMG на тот же том, что и текущее
        //    приложение. replaceItemAt НЕ умеет переносить элемент напрямую с
        //    read-only тома DMG — именно это давало «Ошибку установки».
        let stagingDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("RuSwitcher-update-staging", isDirectory: true)
        try? fm.removeItem(at: stagingDir)
        let stagedApp = stagingDir.appendingPathComponent(appName)
        do {
            try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
            try fm.copyItem(at: sourceApp, to: stagedApp)
        } catch {
            rslog("Update: staging copy failed — \(error)")
            await showInstallError(error.localizedDescription)
            return
        }
        defer { try? fm.removeItem(at: stagingDir) }

        // 7. Атомарно заменить .app из staging-копии (на одном томе — работает)
        do {
            _ = try fm.replaceItemAt(currentApp, withItemAt: stagedApp)
            rslog("Update: app replaced successfully")
        } catch {
            rslog("Update: replace failed — \(error)")
            await showInstallError(error.localizedDescription)
            return
        }

        // 8. Перезапуск
        rslog("Update: restarting...")
        AppRelauncher.relaunch(bundlePath: currentApp.path)
    }

    /// Проверяет, что бандл подписан Developer ID нашей команды и проходит строгую
    /// проверку целостности (codesign --verify с пиннингом Team ID).
    private static func verifyNotarizedSignature(at path: String) -> Bool {
        let requirement = "anchor apple generic and certificate leaf[subject.OU] = \"\(SettingsManager.developerTeamID)\""
        let process = Process()
        process.launchPath = "/usr/bin/codesign"
        process.arguments = ["--verify", "--deep", "--strict", "-R=\(requirement)", path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            rslog("Update: codesign verify error — \(error)")
            return false
        }
    }

    private static func sha256OfFile(at path: String) -> String? {
        let pipe = Pipe()
        let process = Process()
        process.launchPath = "/usr/bin/shasum"
        process.arguments = ["-a", "256", path]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return nil }
            return output.split(separator: " ").first.map(String.init)
        } catch {
            return nil
        }
    }

    private static func showAlert(style: NSAlert.Style, title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static func showInstallError(_ message: String) async {
        showAlert(style: .warning, title: L10n.updateInstallFailed, message: message)
    }

    private static func showUpToDateAlert() async {
        showAlert(style: .informational, title: L10n.updateUpToDate, message: L10n.updateLatestInstalled)
    }

    private static func showErrorAlert() async {
        showAlert(style: .warning, title: L10n.updateCheckFailed, message: L10n.updateCheckFailedDetail)
    }

    /// Сравнивает версии ("2.0.1" > "1.9.0")
    private static func compareVersions(_ v1: String, isNewerThan v2: String) -> Bool {
        let parts1 = v1.split(separator: ".").compactMap { Int($0) }
        let parts2 = v2.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(parts1.count, parts2.count) {
            let p1 = i < parts1.count ? parts1[i] : 0
            let p2 = i < parts2.count ? parts2[i] : 0
            if p1 > p2 { return true }
            if p1 < p2 { return false }
        }
        return false
    }
}

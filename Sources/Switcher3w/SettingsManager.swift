import Foundation
import ServiceManagement

/// Centralized settings storage via UserDefaults
/// Application settings. Properties are thread-safe through UserDefaults.
final class SettingsManager: @unchecked Sendable {
    static let shared = SettingsManager()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let autoSwitch = "com.switcher3w.autoSwitch"
        static let layout1ID = "com.switcher3w.layout1ID"
        static let layout2ID = "com.switcher3w.layout2ID"
        static let debugLog = "com.switcher3w.debugLog"
        static let launchAtLogin = "com.switcher3w.launchAtLogin"
        static let interfaceLanguage = "com.switcher3w.interfaceLanguage"
        static let permissionsWereGranted = "com.switcher3w.permissionsWereGranted"
        static let launchAtLoginAsked = "com.switcher3w.launchAtLoginAsked"
        static let perAppLayout = "com.switcher3w.perAppLayout"
        static let triggerKey = "com.switcher3w.triggerKey"
        static let triggerRightOnly = "com.switcher3w.triggerRightOnly"
        static let triggerDoubleTap = "com.switcher3w.triggerDoubleTap"
        static let autoConvert = "com.switcher3w.autoConvert"
        static let remoteDesktopMode = "com.switcher3w.remoteDesktopMode"
        static let showRemoteDesktopBeta = "com.switcher3w.showRemoteDesktopBeta"
        static let autoConvertOffered = "com.switcher3w.autoConvertOffered"
        static let keySound = "com.switcher3w.keySound"
        static let caretFlag = "com.switcher3w.caretFlag"
        static let deniedAppsAdded = "com.switcher3w.deniedAppsAdded"
        static let deniedAppsRemoved = "com.switcher3w.deniedAppsRemoved"
        static let deniedWords = "com.switcher3w.deniedWords"
        static let alwaysConvertWords = "com.switcher3w.alwaysConvertWords"
        static let pausedUntil = "com.switcher3w.pausedUntil"
    }

    private init() {}

    // MARK: - Key migration

    /// One-time migration of settings from the old com.ruswitcher.* keys (inherited
    /// from upstream) to com.switcher3w.*. Called from main.swift BEFORE any settings
    /// read (including lazy language initialization in L10n). Old values are not
    /// removed — insurance in case of a rollback to a previous build.
    static func migrateLegacyDefaults() {
        let d = UserDefaults.standard
        let marker = "com.switcher3w.migratedLegacyKeys"
        guard !d.bool(forKey: marker) else { return }
        let oldPrefix = "com.ruswitcher."
        let newPrefix = "com.switcher3w."
        var migrated = 0
        for (key, value) in d.dictionaryRepresentation() where key.hasPrefix(oldPrefix) {
            let newKey = newPrefix + key.dropFirst(oldPrefix.count)
            if d.object(forKey: newKey) == nil {
                d.set(value, forKey: newKey)
                migrated += 1
            }
        }
        d.set(true, forKey: marker)
        rslog("Settings migration: \(migrated) legacy com.ruswitcher.* keys copied")
    }

    // MARK: - Properties

    var autoSwitchEnabled: Bool {
        get { defaults.object(forKey: Keys.autoSwitch) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.autoSwitch) }
    }

    // MARK: - Pause (W4)

    /// "Until restart" pause — session-only, NOT persistent: after a relaunch
    /// the app always resumes (that's the point of this pause variant).
    private var pausedUntilRestart = false

    /// Timer-based pause. A separate key from autoSwitch: the pause must not overwrite
    /// the user's saved preference (that checkbox survives a restart, the pause does not).
    var pausedUntil: Date? {
        get { defaults.object(forKey: Keys.pausedUntil) as? Date }
        set { defaults.set(newValue, forKey: Keys.pausedUntil) }
    }

    /// Single source of truth for "paused" (timer-based or until restart).
    var isPaused: Bool {
        if pausedUntilRestart { return true }
        if let until = pausedUntil, until > Date() { return true }
        return false
    }

    /// Sets a pause: interval in seconds, nil = until restart.
    func pause(for interval: TimeInterval?) {
        if let interval {
            pausedUntil = Date().addingTimeInterval(interval)
            pausedUntilRestart = false
        } else {
            pausedUntilRestart = true
            pausedUntil = nil
        }
    }

    /// Clears the pause (manual Resume or an expired timer).
    func clearPause() {
        pausedUntilRestart = false
        pausedUntil = nil
    }

    /// Effective "working": master toggle AND not paused. Gates the trigger and auto-fix.
    var effectivelyEnabled: Bool { autoSwitchEnabled && !isPaused }

    /// ID of the first layout (empty string = auto-detect)
    var layout1ID: String {
        get { defaults.string(forKey: Keys.layout1ID) ?? "" }
        set { defaults.set(newValue, forKey: Keys.layout1ID) }
    }

    /// ID of the second layout (empty string = auto-detect)
    var layout2ID: String {
        get { defaults.string(forKey: Keys.layout2ID) ?? "" }
        set { defaults.set(newValue, forKey: Keys.layout2ID) }
    }

    var debugLogEnabled: Bool {
        get { defaults.bool(forKey: Keys.debugLog) }
        set { defaults.set(newValue, forKey: Keys.debugLog) }
    }

    var launchAtLogin: Bool {
        get { defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false }
        set {
            defaults.set(newValue, forKey: Keys.launchAtLogin)
            let enabled = newValue
            DispatchQueue.main.async {
                self.doUpdateLoginItem(enabled: enabled)
            }
        }
    }

    /// Interface language (empty string = auto-detect from the system)
    var interfaceLanguage: String {
        get { defaults.string(forKey: Keys.interfaceLanguage) ?? "" }
        set {
            defaults.set(newValue, forKey: Keys.interfaceLanguage)
            L10n.reloadLanguage()
        }
    }

    /// Flag: permissions were previously granted (to detect a reset after an update)
    var permissionsWereGranted: Bool {
        get { defaults.bool(forKey: Keys.permissionsWereGranted) }
        set { defaults.set(newValue, forKey: Keys.permissionsWereGranted) }
    }

    var launchAtLoginAsked: Bool {
        get { defaults.bool(forKey: Keys.launchAtLoginAsked) }
        set { defaults.set(newValue, forKey: Keys.launchAtLoginAsked) }
    }

    var perAppLayout: Bool {
        get { defaults.bool(forKey: Keys.perAppLayout) }
        set { defaults.set(newValue, forKey: Keys.perAppLayout) }
    }

    // MARK: - Conversion trigger

    /// Trigger key: "option" | "command" | "control" | "shift" | "capsLock".
    /// Default is option (as it was before 2.3, behavior unchanged).
    var triggerKey: String {
        get { defaults.string(forKey: Keys.triggerKey) ?? "option" }
        set { defaults.set(newValue, forKey: Keys.triggerKey) }
    }

    /// React only to the right modifier key (for option/command/control/shift).
    var triggerRightOnly: Bool {
        get { defaults.bool(forKey: Keys.triggerRightOnly) }
        set { defaults.set(newValue, forKey: Keys.triggerRightOnly) }
    }

    /// Double tap instead of single.
    var triggerDoubleTap: Bool {
        get { defaults.bool(forKey: Keys.triggerDoubleTap) }
        set { defaults.set(newValue, forKey: Keys.triggerDoubleTap) }
    }

    /// Caps Lock as a trigger requires a consume-tap (to suppress the case toggle).
    var triggerIsCapsLock: Bool { triggerKey == "capsLock" }

    /// Automatic "on the fly" conversion (detects the wrong layout at a word
    /// boundary). A separate flag from autoSwitchEnabled (that one gates the MANUAL trigger).
    /// OFF by default — precision matters more, we do nothing without explicit opt-in.
    var autoConvert: Bool {
        get { defaults.bool(forKey: Keys.autoConvert) }
        set { defaults.set(newValue, forKey: Keys.autoConvert) }
    }

    /// issue #10: show the layout flag at the text caret (beta). OFF by default.
    var caretFlag: Bool {
        get { defaults.bool(forKey: Keys.caretFlag) }
        set { defaults.set(newValue, forKey: Keys.caretFlag) }
    }

    /// Remote desktop working mode (Apple Screen Sharing, etc.).
    /// When enabled: the tap is raised to session level (sees forwarded
    /// keystrokes), and the instance "defers to the remote desktop" if a remote desktop client is focused.
    var remoteDesktopMode: Bool {
        get { defaults.bool(forKey: Keys.remoteDesktopMode) }
        set { defaults.set(newValue, forKey: Keys.remoteDesktopMode) }
    }

    /// Whether to show the "Remote desktop mode" toggle (visible beta in 2.5). ON by
    /// default; can be hidden explicitly: `defaults write com.switcher3way.app com.switcher3w.showRemoteDesktopBeta -bool NO`.
    var showRemoteDesktopBeta: Bool {
        get {
            // No entry in defaults → treat as enabled (default ON for 2.5).
            if defaults.object(forKey: Keys.showRemoteDesktopBeta) == nil { return true }
            return defaults.bool(forKey: Keys.showRemoteDesktopBeta)
        }
        set { defaults.set(newValue, forKey: Keys.showRemoteDesktopBeta) }
    }

    /// Whether auto-fix was already offered on first launch (onboarding is shown once).
    var autoConvertOffered: Bool {
        get { defaults.bool(forKey: Keys.autoConvertOffered) }
        set { defaults.set(newValue, forKey: Keys.autoConvertOffered) }
    }

    /// issue #7: layout sound on the first letter after a layout change. OFF by default.
    var keySound: Bool {
        get { defaults.bool(forKey: Keys.keySound) }
        set { defaults.set(newValue, forKey: Keys.keySound) }
    }

    /// Apps where auto-conversion is disabled. The effective list = defaults minus
    /// entries the user explicitly removed plus explicitly added ones. This way new defaults from future
    /// versions are picked up automatically, while the user's edits are preserved.
    var deniedApps: [String] {
        get {
            let removed = Set(defaults.stringArray(forKey: Keys.deniedAppsRemoved) ?? [])
            let added = defaults.stringArray(forKey: Keys.deniedAppsAdded) ?? []
            var result = AutoSwitchPolicy.defaultDeniedApps.filter { !removed.contains($0) }
            for a in added where !result.contains(a) { result.append(a) }
            return result
        }
        set {
            let defaultsSet = Set(AutoSwitchPolicy.defaultDeniedApps)
            let newSet = Set(newValue)
            let removed = AutoSwitchPolicy.defaultDeniedApps.filter { !newSet.contains($0) }
            let added = newValue.filter { !defaultsSet.contains($0) }
            defaults.set(removed, forKey: Keys.deniedAppsRemoved)
            defaults.set(added, forKey: Keys.deniedAppsAdded)
        }
    }

    /// Words that auto-conversion never touches.
    var deniedWords: [String] {
        get { defaults.stringArray(forKey: Keys.deniedWords) ?? [] }
        set { defaults.set(newValue, forKey: Keys.deniedWords) }
    }
    var deniedWordsSet: Set<String> { Set(deniedWords.map { $0.lowercased() }) }

    /// Words that auto-conversion always switches (even if they are not in the dictionary).
    var alwaysConvertWords: [String] {
        get { defaults.stringArray(forKey: Keys.alwaysConvertWords) ?? [] }
        set { defaults.set(newValue, forKey: Keys.alwaysConvertWords) }
    }
    var alwaysConvertWordsSet: Set<String> { Set(alwaysConvertWords.map { $0.lowercased() }) }

    // MARK: - Login Item

    private func doUpdateLoginItem(enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
                rslog("Login item registered")
            } else {
                try service.unregister()
                rslog("Login item unregistered")
            }
        } catch {
            rslog("Login item error: \(error)")
        }
    }

    /// Current launch-at-login status (may differ from the setting)
    var loginItemStatus: SMAppService.Status {
        SMAppService.mainApp.status
    }
}

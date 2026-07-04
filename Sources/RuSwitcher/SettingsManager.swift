import Foundation
import ServiceManagement

/// Централизованное хранение настроек через UserDefaults
/// Настройки приложения. Свойства thread-safe через UserDefaults.
final class SettingsManager: @unchecked Sendable {
    static let shared = SettingsManager()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let autoSwitch = "com.ruswitcher.autoSwitch"
        static let layout1ID = "com.ruswitcher.layout1ID"
        static let layout2ID = "com.ruswitcher.layout2ID"
        static let debugLog = "com.ruswitcher.debugLog"
        static let skippedVersion = "com.ruswitcher.skippedVersion"
        static let lastUpdateCheck = "com.ruswitcher.lastUpdateCheck"
        static let launchAtLogin = "com.ruswitcher.launchAtLogin"
        static let checkUpdatesEnabled = "com.ruswitcher.checkUpdatesEnabled"
        static let interfaceLanguage = "com.ruswitcher.interfaceLanguage"
        static let permissionsWereGranted = "com.ruswitcher.permissionsWereGranted"
        static let launchAtLoginAsked = "com.ruswitcher.launchAtLoginAsked"
        static let perAppLayout = "com.ruswitcher.perAppLayout"
        static let triggerKey = "com.ruswitcher.triggerKey"
        static let triggerRightOnly = "com.ruswitcher.triggerRightOnly"
        static let triggerDoubleTap = "com.ruswitcher.triggerDoubleTap"
        static let autoConvert = "com.ruswitcher.autoConvert"
        static let remoteDesktopMode = "com.ruswitcher.remoteDesktopMode"
        static let showRemoteDesktopBeta = "com.ruswitcher.showRemoteDesktopBeta"
        static let autoConvertOffered = "com.ruswitcher.autoConvertOffered"
        static let keySound = "com.ruswitcher.keySound"
        static let caretFlag = "com.ruswitcher.caretFlag"
        static let deniedAppsAdded = "com.ruswitcher.deniedAppsAdded"
        static let deniedAppsRemoved = "com.ruswitcher.deniedAppsRemoved"
        static let deniedWords = "com.ruswitcher.deniedWords"
        static let alwaysConvertWords = "com.ruswitcher.alwaysConvertWords"
        static let pausedUntil = "com.ruswitcher.pausedUntil"
    }

    private init() {}

    // MARK: - Properties

    var autoSwitchEnabled: Bool {
        get { defaults.object(forKey: Keys.autoSwitch) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.autoSwitch) }
    }

    // MARK: - Пауза (W4)

    /// Пауза «до перезапуска» — только на сессию, НЕ персистится: после релонча
    /// приложение всегда возобновляется (в этом смысл этого варианта паузы).
    private var pausedUntilRestart = false

    /// Таймерная пауза. Отдельный ключ от autoSwitch: пауза не должна затирать
    /// сохранённое предпочтение пользователя (та галочка переживает перезапуск, пауза — нет).
    var pausedUntil: Date? {
        get { defaults.object(forKey: Keys.pausedUntil) as? Date }
        set { defaults.set(newValue, forKey: Keys.pausedUntil) }
    }

    /// Единый источник истины для «на паузе» (таймерная или до перезапуска).
    var isPaused: Bool {
        if pausedUntilRestart { return true }
        if let until = pausedUntil, until > Date() { return true }
        return false
    }

    /// Ставит паузу: interval в секундах, nil = до перезапуска.
    func pause(for interval: TimeInterval?) {
        if let interval {
            pausedUntil = Date().addingTimeInterval(interval)
            pausedUntilRestart = false
        } else {
            pausedUntilRestart = true
            pausedUntil = nil
        }
    }

    /// Снимает паузу (ручной Resume или истёкший таймер).
    func clearPause() {
        pausedUntilRestart = false
        pausedUntil = nil
    }

    /// Эффективное «работаем»: мастер-тумблер И не на паузе. Гейтит триггер и автозамену.
    var effectivelyEnabled: Bool { autoSwitchEnabled && !isPaused }

    /// ID первой раскладки (пустая строка = авто-определение)
    var layout1ID: String {
        get { defaults.string(forKey: Keys.layout1ID) ?? "" }
        set { defaults.set(newValue, forKey: Keys.layout1ID) }
    }

    /// ID второй раскладки (пустая строка = авто-определение)
    var layout2ID: String {
        get { defaults.string(forKey: Keys.layout2ID) ?? "" }
        set { defaults.set(newValue, forKey: Keys.layout2ID) }
    }

    var debugLogEnabled: Bool {
        get { defaults.bool(forKey: Keys.debugLog) }
        set { defaults.set(newValue, forKey: Keys.debugLog) }
    }

    var skippedVersion: String {
        get { defaults.string(forKey: Keys.skippedVersion) ?? "" }
        set { defaults.set(newValue, forKey: Keys.skippedVersion) }
    }

    var lastUpdateCheck: Date? {
        get { defaults.object(forKey: Keys.lastUpdateCheck) as? Date }
        set { defaults.set(newValue, forKey: Keys.lastUpdateCheck) }
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

    /// Авто-проверка обновлений при запуске (дефолт: включено).
    /// На ручную проверку через меню не влияет.
    var checkUpdatesEnabled: Bool {
        get { defaults.object(forKey: Keys.checkUpdatesEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.checkUpdatesEnabled) }
    }

    /// Язык интерфейса (пустая строка = авто-определение по системе)
    var interfaceLanguage: String {
        get { defaults.string(forKey: Keys.interfaceLanguage) ?? "" }
        set {
            defaults.set(newValue, forKey: Keys.interfaceLanguage)
            L10n.reloadLanguage()
        }
    }

    /// Флаг: разрешения были ранее выданы (для определения сброса после обновления)
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

    // MARK: - Триггер конвертации

    /// Клавиша-триггер: "option" | "command" | "control" | "shift" | "capsLock".
    /// Дефолт — option (как было до 2.3, поведение не меняется).
    var triggerKey: String {
        get { defaults.string(forKey: Keys.triggerKey) ?? "option" }
        set { defaults.set(newValue, forKey: Keys.triggerKey) }
    }

    /// Реагировать только на правую клавишу модификатора (для option/command/control/shift).
    var triggerRightOnly: Bool {
        get { defaults.bool(forKey: Keys.triggerRightOnly) }
        set { defaults.set(newValue, forKey: Keys.triggerRightOnly) }
    }

    /// Двойной тап вместо одиночного.
    var triggerDoubleTap: Bool {
        get { defaults.bool(forKey: Keys.triggerDoubleTap) }
        set { defaults.set(newValue, forKey: Keys.triggerDoubleTap) }
    }

    /// Caps Lock как триггер требует consume-tap (чтобы подавить переключение регистра).
    var triggerIsCapsLock: Bool { triggerKey == "capsLock" }

    /// Автоматическая конвертация «на лету» (детект неправильной раскладки на границе
    /// слова). Отдельный флаг от autoSwitchEnabled (тот гейтит РУЧНОЙ триггер).
    /// По умолчанию ВЫКЛ — точность важнее, не делаем ничего без явного включения.
    var autoConvert: Bool {
        get { defaults.bool(forKey: Keys.autoConvert) }
        set { defaults.set(newValue, forKey: Keys.autoConvert) }
    }

    /// issue #10: показывать флаг раскладки у текстовой каретки (бета). По умолчанию ВЫКЛ.
    var caretFlag: Bool {
        get { defaults.bool(forKey: Keys.caretFlag) }
        set { defaults.set(newValue, forKey: Keys.caretFlag) }
    }

    /// Режим работы через удалённый рабочий стол (Apple Screen Sharing и т.п.).
    /// При включении: tap поднимается на session-уровень (видит проброшенные
    /// нажатия), и инстанс «уступает удалёнке», если в фокусе клиент удалёнки.
    var remoteDesktopMode: Bool {
        get { defaults.bool(forKey: Keys.remoteDesktopMode) }
        set { defaults.set(newValue, forKey: Keys.remoteDesktopMode) }
    }

    /// Показывать ли тумблер «Режим удалённого стола» (видимая бета в 2.5). По умолчанию
    /// ВКЛючён; спрятать можно явно: `defaults write com.ruswitcher.app com.ruswitcher.showRemoteDesktopBeta -bool NO`.
    var showRemoteDesktopBeta: Bool {
        get {
            // Нет записи в defaults → считаем включённым (дефолт ON для 2.5).
            if defaults.object(forKey: Keys.showRemoteDesktopBeta) == nil { return true }
            return defaults.bool(forKey: Keys.showRemoteDesktopBeta)
        }
        set { defaults.set(newValue, forKey: Keys.showRemoteDesktopBeta) }
    }

    /// Предлагали ли уже автозамену при первом запуске (онбординг показывается один раз).
    var autoConvertOffered: Bool {
        get { defaults.bool(forKey: Keys.autoConvertOffered) }
        set { defaults.set(newValue, forKey: Keys.autoConvertOffered) }
    }

    /// issue #7: звук раскладки на первой букве после смены раскладки. По умолчанию OFF.
    var keySound: Bool {
        get { defaults.bool(forKey: Keys.keySound) }
        set { defaults.set(newValue, forKey: Keys.keySound) }
    }

    /// Приложения, где авто-конверсия выключена. Эффективный список = дефолты минус
    /// явно удалённые пользователем плюс явно добавленные. Так новые дефолты из будущих
    /// версий подхватываются автоматически, а правки пользователя сохраняются.
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

    /// Слова, которые авто-конверсия никогда не трогает.
    var deniedWords: [String] {
        get { defaults.stringArray(forKey: Keys.deniedWords) ?? [] }
        set { defaults.set(newValue, forKey: Keys.deniedWords) }
    }
    var deniedWordsSet: Set<String> { Set(deniedWords.map { $0.lowercased() }) }

    /// Слова, которые авто-конверсия переключает всегда (даже если их нет в словаре).
    var alwaysConvertWords: [String] {
        get { defaults.stringArray(forKey: Keys.alwaysConvertWords) ?? [] }
        set { defaults.set(newValue, forKey: Keys.alwaysConvertWords) }
    }
    var alwaysConvertWordsSet: Set<String> { Set(alwaysConvertWords.map { $0.lowercased() }) }

    var donateURL: String { "https://boosty.to/ruswitcher" }
    var contactEmail: String { "xrashid@gmail.com" }

    // MARK: - GitHub coordinates (единственный источник — чтобы при переименовании
    // репозитория правка была в одном месте)
    static let githubOwner = "rashn"
    static let githubRepo = "RuSwitcher"
    static var githubURL: String { "https://github.com/\(githubOwner)/\(githubRepo)" }
    /// Team ID (Apple Developer), которым подписаны релизы. Используется для
    /// пиннинга подписи при авто-обновлении.
    static let developerTeamID = "9GEWCZ59HK"
    static func releaseDMGURL(version: String) -> String {
        "\(githubURL)/releases/download/v\(version)/\(githubRepo)-\(version).dmg"
    }

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

    /// Текущий статус автозапуска (может отличаться от настройки)
    var loginItemStatus: SMAppService.Status {
        SMAppService.mainApp.status
    }
}

import Carbon
import Foundation

/// Управление раскладками через TIS API
enum LayoutSwitcher {
    /// Возвращает ID текущей раскладки
    static func currentLayoutID() -> String {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return ""
        }
        return sourceID(source)
    }

    /// Код языка ТЕКУЩЕЙ раскладки (BCP-47, например "ru"/"en"). nil если недоступен.
    /// Надёжнее парсинга ID: тот же признак, что использует сама ОС.
    static func currentLanguageCode() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        return languageCode(source)
    }

    /// Имя ТЕКУЩЕЙ раскладки в языке интерфейса (для статусного заголовка меню, W4).
    static func currentLayoutName() -> String {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return ""
        }
        return displayName(source)
    }

    /// Имя раскладки, согласованное с языком интерфейса приложения: системно-
    /// локализованное, когда языки совпадают; иначе — нейтральное из ID источника
    /// (kTISPropertyLocalizedName локализуется по СИСТЕМЕ, не по приложению,
    /// и на «русской» macOS с английским интерфейсом давало «Русская»).
    static func displayName(_ source: TISInputSource) -> String {
        if L10n.namesFollowSystem { return sourceName(source) }
        let last = sourceID(source).components(separatedBy: ".").last ?? ""
        guard !last.isEmpty else { return sourceName(source) }
        return last.replacingOccurrences(of: "-", with: " ")
    }

    /// Переключает на СЛЕДУЮЩУЮ установленную раскладку (по кругу). Фолбэк там, где рендер
    /// набранного по раскладкам невозможен (удалёнка/выделение мышью): фиксированной пары
    /// больше нет, поэтому просто листаем установленные источники.
    static func switchToNextInstalled() {
        let sources = installedLayouts()
        guard !sources.isEmpty else { return }
        let currentID = currentLayoutID()
        let idx = sources.firstIndex(where: { sourceID($0) == currentID }) ?? -1
        let target = sources[(idx + 1) % sources.count]
        TISEnableInputSource(target)
        TISSelectInputSource(target)
    }

    /// Переключает на конкретную раскладку по точному ID
    static func switchTo(layoutID: String) {
        let sources = installedLayouts()
        if let target = sources.first(where: { sourceID($0) == layoutID }) {
            TISEnableInputSource(target)
            TISSelectInputSource(target)
        }
    }

    /// Все установленные раскладки
    static func installedLayouts() -> [TISInputSource] {
        let conditions: CFDictionary = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as Any,
            kTISPropertyInputSourceIsSelectCapable as String: true as Any,
        ] as CFDictionary

        guard let list = TISCreateInputSourceList(conditions, false)?.takeRetainedValue() as? [TISInputSource] else {
            return []
        }
        return list
    }

    /// ID раскладки (например "com.apple.keylayout.Russian")
    static func sourceID(_ source: TISInputSource) -> String {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return ""
        }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    /// Локализованное имя раскладки (например "Русская")
    static func sourceName(_ source: TISInputSource) -> String {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else {
            return sourceID(source)
        }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    /// Код языка раскладки (BCP-47, например "ru", "en"), из kTISPropertyInputSourceLanguages
    static func languageCode(_ source: TISInputSource) -> String? {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else {
            return nil
        }
        let langs = Unmanaged<CFArray>.fromOpaque(ptr).takeUnretainedValue() as? [String]
        return langs?.first
    }

    // MARK: - Auto-detect

    /// Авто-определение «английской» раскладки (используется и из DynamicKeyMapping).
    static func autoDetectID1(from sources: [TISInputSource]) -> String {
        // Ищем английскую
        for source in sources {
            let id = sourceID(source)
            if id.contains("ABC") || id.contains("US") || id.contains("British") {
                return id
            }
        }
        return sources.first.map { sourceID($0) } ?? ""
    }

    /// Авто-определение второй (не-английской) раскладки.
    static func autoDetectID2(from sources: [TISInputSource]) -> String {
        let id1 = autoDetectID1(from: sources)
        // Ищем вторую (не английскую)
        for source in sources {
            let id = sourceID(source)
            if id != id1 {
                return id
            }
        }
        return ""
    }
}

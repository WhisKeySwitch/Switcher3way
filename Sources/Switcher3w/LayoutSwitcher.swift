import Carbon
import Foundation

/// Layout control via the TIS API
enum LayoutSwitcher {
    /// Returns the ID of the current layout
    static func currentLayoutID() -> String {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return ""
        }
        return sourceID(source)
    }

    /// Language code of the CURRENT layout (BCP-47, e.g. "ru"/"en"). nil if unavailable.
    /// More reliable than parsing the ID: the same attribute the OS itself uses.
    static func currentLanguageCode() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        return languageCode(source)
    }

    /// Name of the CURRENT layout in the interface language (for the menu status header, W4).
    static func currentLayoutName() -> String {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return ""
        }
        return displayName(source)
    }

    /// Layout name consistent with the app's interface language: system-
    /// localized when the languages match; otherwise — a neutral name from the source ID
    /// (kTISPropertyLocalizedName is localized by the SYSTEM, not the app,
    /// and on "Russian" macOS with an English interface it produced the Russian name).
    static func displayName(_ source: TISInputSource) -> String {
        if L10n.namesFollowSystem { return sourceName(source) }
        let last = sourceID(source).components(separatedBy: ".").last ?? ""
        guard !last.isEmpty else { return sourceName(source) }
        return last.replacingOccurrences(of: "-", with: " ")
    }

    /// Switches to the NEXT installed layout (cycling). A fallback where rendering
    /// the typed text through layouts is impossible (remote desktop/mouse selection): there is
    /// no fixed pair anymore, so we just cycle through the installed sources.
    static func switchToNextInstalled() {
        let sources = installedLayouts()
        guard !sources.isEmpty else { return }
        let currentID = currentLayoutID()
        let idx = sources.firstIndex(where: { sourceID($0) == currentID }) ?? -1
        let target = sources[(idx + 1) % sources.count]
        TISEnableInputSource(target)
        TISSelectInputSource(target)
    }

    /// Switches to a specific layout by its exact ID
    static func switchTo(layoutID: String) {
        let sources = installedLayouts()
        if let target = sources.first(where: { sourceID($0) == layoutID }) {
            TISEnableInputSource(target)
            TISSelectInputSource(target)
        }
    }

    /// All installed layouts
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

    /// Layout ID (e.g. "com.apple.keylayout.Russian")
    static func sourceID(_ source: TISInputSource) -> String {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return ""
        }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    /// Localized layout name (e.g. "Russian")
    static func sourceName(_ source: TISInputSource) -> String {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else {
            return sourceID(source)
        }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    /// Layout language code (BCP-47, e.g. "ru", "en"), from kTISPropertyInputSourceLanguages
    static func languageCode(_ source: TISInputSource) -> String? {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else {
            return nil
        }
        let langs = Unmanaged<CFArray>.fromOpaque(ptr).takeUnretainedValue() as? [String]
        return langs?.first
    }

    // MARK: - Auto-detect

    /// Auto-detection of the "English" layout (also used from DynamicKeyMapping).
    static func autoDetectID1(from sources: [TISInputSource]) -> String {
        // Look for the English one
        for source in sources {
            let id = sourceID(source)
            if id.contains("ABC") || id.contains("US") || id.contains("British") {
                return id
            }
        }
        return sources.first.map { sourceID($0) } ?? ""
    }

    /// Auto-detection of the second (non-English) layout.
    static func autoDetectID2(from sources: [TISInputSource]) -> String {
        let id1 = autoDetectID1(from: sources)
        // Look for the second (non-English) one
        for source in sources {
            let id = sourceID(source)
            if id != id1 {
                return id
            }
        }
        return ""
    }
}

import AppKit
import Carbon
import Switcher3wCore

/// Production conformances that bind the platform-free core to macOS. The core states what it
/// needs (a dictionary, a layout catalog, the user's word lists); these supply it from
/// NSSpellChecker, the TIS input-source APIs, and UserDefaults.

/// `NSSpellChecker` behind the core's validator interface.
@MainActor
struct SystemDictionary: DictionaryValidating {
    func isAvailable(_ lang: String) -> Bool { Dict.isAvailable(lang) }
    func isValidWord(_ word: String, lang: String) -> Bool { Dict.isValidWord(word, lang: lang) }
}

/// The TIS input sources behind the core's layout interface. `Layout` carries only the id and the
/// 2-letter language, so `TISInputSource` never crosses into the core.
@MainActor
struct SystemLayoutCatalog: LayoutCatalog {
    func installedLayouts() -> [Layout] {
        LayoutSwitcher.installedLayouts().compactMap { source in
            guard let lang = LayoutSwitcher.languageCode(source) else { return nil }
            return Layout(id: LayoutSwitcher.sourceID(source), lang: lang)
        }
    }

    func currentLayoutID() -> String { LayoutSwitcher.currentLayoutID() }

    func render(_ keys: [TypedKey], layoutID: String) -> String? {
        guard let source = LayoutSwitcher.installedLayouts()
            .first(where: { LayoutSwitcher.sourceID($0) == layoutID }),
              let data = DynamicKeyMapping.layoutDataForSource(source) else { return nil }
        var out = ""
        for k in keys {
            guard let c = DynamicKeyMapping.translateKeycode(k.keyCode, layoutData: data,
                                                             shift: k.shift, caps: k.caps) else {
                return nil
            }
            out.append(c)
        }
        return out
    }
}

/// The user's never-convert / always-convert lists behind the core's interface.
@MainActor
struct SettingsExceptionList: WordExceptionList {
    func isAlwaysConvert(_ converted: String) -> Bool { AutoSwitchPolicy.isAlwaysConvert(converted) }
    func isNeverConvert(_ typed: String, _ converted: String) -> Bool {
        AutoSwitchPolicy.isDeniedWord(typed, converted)
    }
}

/// The app's single resolver. The core is instance-based (its dependencies are injected), so the
/// executable owns one wired to the system adapters — mirroring the Windows port's `_resolver`.
@MainActor
enum NWay {
    static let resolver = NWayResolver(catalog: SystemLayoutCatalog(),
                                       dict: SystemDictionary(),
                                       exceptions: SettingsExceptionList())

    /// Wires the core's log sink to `rslog`. Call once at startup, before anything evaluates.
    static func installLogSink() {
        CoreLog.install { rslog($0) }
    }
}

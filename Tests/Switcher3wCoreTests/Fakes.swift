import Foundation
@testable import Switcher3wCore

/// Deterministic stand-ins for the platform services, modelled on the Windows port's
/// `tests/Switcher3way.Core.Tests/Fakes.cs`. Without these the results would depend on which
/// layouts and system dictionaries the developer's machine happens to have installed.

/// A dictionary with a fixed word set per language.
@MainActor
final class FakeDictionary: DictionaryValidating {
    var words: [String: Set<String>]
    /// Languages that report "no dictionary installed" regardless of their word set.
    var unavailable: Set<String> = []

    init(_ words: [String: Set<String>]) {
        self.words = words
    }

    func isAvailable(_ lang: String) -> Bool {
        !unavailable.contains(lang) && words[lang] != nil
    }

    func isValidWord(_ word: String, lang: String) -> Bool {
        words[lang]?.contains(word.lowercased()) ?? false
    }
}

/// A layout catalog driven by explicit character tables: each layout maps a keycode to the
/// character it produces, so "typing" in a test is just a list of keycodes.
@MainActor
final class FakeLayoutCatalog: LayoutCatalog {
    struct FakeLayout {
        let layout: Layout
        /// keycode → (unshifted, shifted)
        let keys: [UInt16: (Character, Character)]
    }

    var layouts: [FakeLayout]
    var current: String
    /// Layout ids whose rendering is deliberately broken (no layout data).
    var unrenderable: Set<String> = []

    init(layouts: [FakeLayout], current: String) {
        self.layouts = layouts
        self.current = current
    }

    func installedLayouts() -> [Layout] { layouts.map(\.layout) }
    func currentLayoutID() -> String { current }

    func render(_ keys: [TypedKey], layoutID: String) -> String? {
        guard !unrenderable.contains(layoutID),
              let l = layouts.first(where: { $0.layout.id == layoutID }) else { return nil }
        var out = ""
        for k in keys {
            guard let pair = l.keys[k.keyCode] else { return nil }
            let base = (k.shift != k.caps) ? pair.1 : pair.0
            out.append(base)
        }
        return out
    }
}

/// Word exception lists as plain sets.
@MainActor
final class FakeExceptions: WordExceptionList {
    var always: Set<String> = []
    var never: Set<String> = []

    func isAlwaysConvert(_ converted: String) -> Bool { always.contains(converted.lowercased()) }
    func isNeverConvert(_ typed: String, _ converted: String) -> Bool {
        never.contains(typed.lowercased()) || never.contains(converted.lowercased())
    }
}

// MARK: - A three-layout fixture (en / uk / ru) on the keys the tests need

@MainActor
enum Fixture {
    static let en = "com.apple.keylayout.US"
    static let uk = "com.apple.keylayout.Ukrainian"
    static let ru = "com.apple.keylayout.Russian"

    /// The QWERTY ↔ ЙЦУКЕН correspondence for the letters used in the test words, plus the two
    /// punctuation keys that differ between layouts (`,`→`б`, `.`→`ю`) and one digit key.
    private static let rows: [(UInt16, Character, Character, Character)] = [
        // keycode, en, uk, ru
        (0,  "a", "ф", "ф"), (1,  "s", "і", "ы"), (2,  "d", "в", "в"), (3,  "f", "а", "а"),
        (4,  "h", "р", "р"), (5,  "g", "п", "п"), (6,  "z", "я", "я"), (7,  "x", "ч", "ч"),
        (8,  "c", "с", "с"), (9,  "v", "м", "м"), (11, "b", "и", "и"), (12, "q", "й", "й"),
        (13, "w", "ц", "ц"), (14, "e", "у", "у"), (15, "r", "к", "к"), (16, "y", "н", "н"),
        (17, "t", "е", "е"), (31, "o", "щ", "щ"), (32, "u", "г", "г"), (34, "i", "ш", "ш"),
        (35, "p", "з", "з"), (37, "l", "д", "д"), (38, "j", "о", "о"), (40, "k", "л", "л"),
        (45, "n", "т", "т"), (46, "m", "ь", "ь"), (39, "'", "є", "э"), (41, ";", "ж", "ж"),
        (43, ",", "б", "б"), (47, ".", "ю", "ю"), (30, "]", "ї", "ъ"), (33, "[", "х", "х"),
        // Shift+1 is "!" on all three layouts — the shared punctuation the letter core trims.
        (18, "1", "1", "1"),
    ]

    /// A SECOND Russian layout (e.g. "Russian – PC" alongside "RussianWin"): same language, same
    /// rendering. Used to prove that same-language duplicates still collapse now that layouts of
    /// DIFFERENT languages no longer do.
    static let ru2 = "com.apple.keylayout.Russian-PC"

    static func catalog(current: String = en, langs: [String] = ["en", "uk", "ru"]) -> FakeLayoutCatalog {
        var made: [FakeLayoutCatalog.FakeLayout] = []
        for lang in langs {
            let id = lang == "en" ? en : (lang == "uk" ? uk : (lang == "ru" ? ru : ru2))
            var keys: [UInt16: (Character, Character)] = [:]
            for (code, e, u, r) in rows {
                let ch: Character = lang == "en" ? e : (lang == "uk" ? u : r)   // ru2 renders as ru
                // Shift on the digit row gives punctuation, not an uppercase letter.
                let shifted: Character = code == 18 ? "!" : Character(String(ch).uppercased())
                keys[code] = (ch, shifted)
            }
            made.append(.init(layout: Layout(id: id, lang: lang == "ru2" ? "ru" : lang), keys: keys))
        }
        return FakeLayoutCatalog(layouts: made, current: current)
    }

    /// Turn a Latin string into the keystrokes that would have produced it on the US layout —
    /// which is how a user types a Cyrillic word while the wrong layout is active.
    static func keys(_ latin: String, caps: Bool = false) -> [TypedKey] {
        latin.map { ch in
            let lower = Character(String(ch).lowercased())
            let code = rows.first { $0.1 == lower }?.0 ?? 0
            return TypedKey(keyCode: code, shift: ch.isUppercase && !caps, caps: caps)
        }
    }
}

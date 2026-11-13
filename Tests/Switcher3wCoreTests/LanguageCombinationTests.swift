#if canImport(AppKit)
import AppKit
import Carbon
import XCTest
@testable import Switcher3wCore

/// What each small combination of detection languages costs and gains, measured on the Mac it runs
/// on: the real `NSSpellChecker`, and layout tables read from the installed input sources with
/// `UCKeyTranslate` rather than written down. A language is admitted only when every two- and
/// three-language combination containing it clears the gate in
/// `openspec/changes/detect-chosen-language-combinations` — this file is that gate.
///
/// Four measurements per combination:
/// - **keep**: each language's prose, typed on its own layout, must move no word;
/// - **typos**: dropped, doubled and transposed letters of each language's prose, typed on its own
///   layout, must convert no more often than the shipped en+uk+ru combination's worst language;
/// - **recall**: each language's prose typed while another layout of the combination is active —
///   reported, not gated;
/// - **wrong**: a recall word the app treats as settled — a single-winner conversion or rescue —
///   converted into a different text than the one intended. Must be zero.
/// - **defaulted**: a tie the preference settled into a different text (`быстро` → `бістро` with a
///   Ukrainian preference). Reported, not gated: the app marks these defaulted and phrase
///   correction owns them, which a per-word measurement cannot see.
///
/// Runs only with `SWITCHER3W_MEASURE_COMBINATIONS=1`: 40 combinations through the real spell
/// checker take minutes. Set `SWITCHER3W_MEASURE_OUT` to a path to also get the figures as TSV.
@MainActor
final class LanguageCombinationTests: XCTestCase {

    // MARK: - Which languages, on which layouts

    /// Each language's default macOS layout — the one a person enabling that language gets.
    static let defaultLayout: [String: String] = [
        "en": "com.apple.keylayout.US",
        "uk": "com.apple.keylayout.Ukrainian-PC",
        "ru": "com.apple.keylayout.RussianWin",
        "bg": "com.apple.keylayout.Bulgarian",
        "de": "com.apple.keylayout.German",
        "fr": "com.apple.keylayout.French",
    ]
    /// Measured as a variant: it transliterates rather than scrambles, which is the Serbian problem.
    static let bulgarianPhonetic = "com.apple.keylayout.Bulgarian-Phonetic"

    /// The languages with a `LanguageProfile`. The gate is enforced only for combinations drawn
    /// from this set; everything else is measured and reported. `bgPh` is held to it too: it is
    /// Bulgarian, and production now keeps it out of the targets, so it must cost nothing.
    static var admitted: Set<String> { Set(LanguageProfile.all.keys).union(["bgPh"]) }

    static let baseline = ["en", "uk", "ru"]

    /// Every two- and three-language combination of the candidates, plus the Bulgarian Phonetic
    /// variant of each combination that pairs Bulgarian with English.
    static var combinations: [[String]] {
        let langs = ["en", "uk", "ru", "bg", "de", "fr"]
        var out: [[String]] = []
        for i in 0..<langs.count {
            for j in (i + 1)..<langs.count {
                out.append([langs[i], langs[j]])
                for k in (j + 1)..<langs.count { out.append([langs[i], langs[j], langs[k]]) }
            }
        }
        let variants = out.filter { $0.contains("en") && $0.contains("bg") }
            .map { $0.map { $0 == "bg" ? "bgPh" : $0 } }
        return out.sorted { ($0.count, $0.joined()) < ($1.count, $1.joined()) } + variants
    }

    static func layoutID(_ member: String) -> String {
        member == "bgPh" ? bulgarianPhonetic : defaultLayout[member]!
    }
    static func lang(_ member: String) -> String { String(member.prefix(2)) }

    // MARK: - Layout tables, read from the system

    /// keycode → (unshifted, shifted) for one input source, or nil if it is not installed.
    typealias Table = [UInt16: (Character?, Character?)]

    static var tableCache: [String: Table?] = [:]

    static func table(_ id: String) -> Table? {
        if let hit = tableCache[id] { return hit }
        let result = readTable(id)
        tableCache[id] = result
        return result
    }

    private static func readTable(_ id: String) -> Table? {
        let props = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let list = TISCreateInputSourceList(props, true)?.takeRetainedValue() as? [TISInputSource],
              let source = list.first,
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        var table: Table = [:]
        data.withUnsafeBytes { bytes in
            let layout = bytes.baseAddress!.assumingMemoryBound(to: UCKeyboardLayout.self)
            func translate(_ code: UInt16, _ modifiers: UInt32) -> Character? {
                var dead: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), modifiers,
                                            UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                            &dead, 4, &length, &chars)
                guard status == noErr, length == 1,
                      let c = String(utf16CodeUnits: chars, count: length).first,
                      !c.isWhitespace, !(c.asciiValue.map { $0 < 32 || $0 == 127 } ?? false) else { return nil }
                return c
            }
            // The typing keys of an ANSI/ISO keyboard: letters, digits and punctuation.
            for code in UInt16(0)...UInt16(50) where ![36, 48, 49].contains(code) {
                let plain = translate(code, 0)
                let shifted = translate(code, UInt32(shiftKey >> 8) & 0xFF)
                if plain != nil || shifted != nil { table[code] = (plain, shifted) }
            }
        }
        return table
    }

    /// Keystrokes that produce `word` on the layout, or nil if a character is not on a single key.
    static func keys(for word: String, on id: String) -> [TypedKey]? {
        guard let t = table(id) else { return nil }
        var out: [TypedKey] = []
        for ch in word {
            if let (code, _) = t.first(where: { $0.value.0 == ch }) {
                out.append(TypedKey(keyCode: code, shift: false, caps: false))
            } else if let (code, _) = t.first(where: { $0.value.1 == ch }) {
                out.append(TypedKey(keyCode: code, shift: true, caps: false))
            } else {
                return nil
            }
        }
        return out
    }

    final class Catalog: LayoutCatalog {
        let members: [String]
        let current: String
        init(_ members: [String], current: String) { self.members = members; self.current = current }
        func installedLayouts() -> [Layout] {
            // Bulgarian Phonetic is flagged as production's catalog flags it.
            members.map { Layout(id: LanguageCombinationTests.layoutID($0), lang: LanguageCombinationTests.lang($0),
                                 transliterates: $0 == "bgPh") }
        }
        func currentLayoutID() -> String { LanguageCombinationTests.layoutID(current) }
        func render(_ keys: [TypedKey], layoutID: String) -> String? {
            guard let t = LanguageCombinationTests.table(layoutID) else { return nil }
            var s = ""
            for k in keys {
                guard let pair = t[k.keyCode], let c = (k.shift ? pair.1 : pair.0) else { return nil }
                s.append(c)
            }
            return s
        }
    }

    // MARK: - The dictionary, as production answers it today

    /// `NSSpellChecker` as the app asks it, memoized: the same words recur across forty
    /// combinations, and the checker's answer to a given word does not change within a run.
    /// Vowels are production's (`LanguageProfile`); the alphabet is derived from the layouts, as
    /// production derives it.
    final class Dict: DictionaryValidating {
        let checker = NSSpellChecker.shared
        var memo: [String: Bool] = [:]

        func isAvailable(_ lang: String) -> Bool {
            checker.availableLanguages.contains { String($0.prefix(2)) == lang }
        }
        func isValidWord(_ word: String, lang: String) -> Bool {
            let key = lang + "|" + word
            if let hit = memo[key] { return hit }
            let ok = checker.checkSpelling(of: word, startingAt: 0, language: lang, wrap: false,
                                           inSpellDocumentWithTag: 0, wordCount: nil).location == NSNotFound
            memo[key] = ok
            return ok
        }
        func alphabet(_ lang: String) -> String {
            let ids = lang == "bg" ? [defaultLayout["bg"]!, bulgarianPhonetic] : [defaultLayout[lang]].compactMap { $0 }
            var seen = Set<Character>()
            var out = ""
            for id in ids {
                for (_, pair) in table(id) ?? [:] {
                    guard let c = pair.0, c.isLetter else { continue }
                    for l in String(c).lowercased() where seen.insert(l).inserted { out.append(l) }
                }
            }
            return out
        }
        func vowels(_ lang: String) -> String { LanguageProfile.of(lang)?.vowels ?? "" }
    }

    struct NoExceptions: WordExceptionList {
        func isAlwaysConvert(_ converted: String) -> Bool { false }
        func isNeverConvert(_ typed: String, _ converted: String) -> Bool { false }
    }

    // MARK: - Words

    /// Tokens as typed: split on whitespace, edge punctuation trimmed, case and inner apostrophes
    /// or hyphens kept — `Haus`, `l'eau`, `по-добре`.
    static func tokens(_ text: String) -> [String] {
        var seen = Set<String>()
        return text.split(whereSeparator: \.isWhitespace).compactMap { raw in
            let t = raw.trimmingCharacters(in: CharacterSet.letters.inverted)
            return t.count >= 2 && seen.insert(t).inserted ? t : nil
        }
    }

    /// Lower-cased tokens, for typos and recall. Split as typed — `aujourd'hui` and `по-добре` stay
    /// whole, because nobody types half of them.
    static func words(_ text: String) -> [String] {
        var seen = Set<String>()
        return tokens(text).map { $0.lowercased() }.filter { seen.insert($0).inserted }
    }

    static func typos(of w: String) -> [String] {
        let a = Array(w)
        var out: [String] = []
        for i in a.indices { var b = a; b.remove(at: i); out.append(String(b)) }
        for i in a.indices { var b = a; b.insert(a[i], at: i); out.append(String(b)) }
        for i in 0..<(a.count - 1) { var b = a; b.swapAt(i, i + 1); out.append(String(b)) }
        return out.filter { $0.count >= 2 && $0 != w }
    }

    // MARK: - Outcomes

    enum Acted { case none, converted(lang: String, text: String), tie }

    /// What the app would do with the word, per word with no phrase: a conversion, a rescue, or a
    /// tie that the default preference (uk) settles. A held word is left alone.
    static func act(_ o: NWayResolver.Outcome) -> (acted: (lang: String, text: String)?, tie: Bool) {
        switch o {
        case .convert(let d), .rescued(let d): return ((d.lang, d.converted), false)
        case .ambiguous(_, let winners):
            let w = NWayResolver.resolveAmbiguity(winners: winners, lockedLang: nil, preference: "uk")?.winner
            return (w.map { ($0.lang, $0.converted) }, true)
        case .keep, .held: return (nil, false)
        }
    }

    // MARK: - The measurement

    struct Row { var combo: String; var kind: String; var lang: String; var hit: Int; var total: Int; var note: String }

    func testEveryCombination() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SWITCHER3W_MEASURE_COMBINATIONS"] == "1",
                          "set SWITCHER3W_MEASURE_COMBINATIONS=1 to run the combination measurement")
        let dict = Dict()

        // What this Mac can measure at all.
        var measurable: Set<String> = []
        for member in ["en", "uk", "ru", "bg", "de", "fr", "bgPh"] {
            let id = Self.layoutID(member), l = Self.lang(member)
            if Self.table(id) == nil { print("combo: skip \(member) — layout \(id) not installed"); continue }
            if !dict.isAvailable(l) { print("combo: skip \(member) — no spell checker for \(l)"); continue }
            measurable.insert(member)
        }
        for (l, text) in CombinationCorpus.prose.sorted(by: { $0.key < $1.key }) {
            let ws = Self.words(text), id = Self.defaultLayout[l]!
            let typable = ws.filter { Self.keys(for: $0, on: id) != nil }.count
            print("combo: corpus \(l): \(ws.count) words, \(typable) typable on \(id.split(separator: ".").last!)")
        }

        var rows: [Row] = []
        // `SWITCHER3W_MEASURE_ONLY=bg` measures only the combinations containing that member (plus
        // the baseline the gate needs); `SWITCHER3W_MEASURE_EXAMPLES` widens the examples per row.
        let only = ProcessInfo.processInfo.environment["SWITCHER3W_MEASURE_ONLY"]
        let examples = Int(ProcessInfo.processInfo.environment["SWITCHER3W_MEASURE_EXAMPLES"] ?? "") ?? 6
        for combo in Self.combinations where combo.allSatisfy(measurable.contains)
            && (only == nil || combo.contains(only!) || combo == Self.baseline) {
            let name = combo.joined(separator: "+")
            let started = Date()

            for member in combo {
                let l = Self.lang(member), id = Self.layoutID(member)
                guard let text = CombinationCorpus.prose[l] else { continue }
                let resolver = NWayResolver(catalog: Catalog(combo, current: member), dict: dict, exceptions: NoExceptions())

                // keep
                var moved: [String] = [], total = 0
                for t in Self.tokens(text) {
                    guard let k = Self.keys(for: t, on: id) else { continue }
                    total += 1
                    if let a = Self.act(resolver.evaluate(keys: k, capsLock: false)).acted { moved.append("\(t)→\(a.text)[\(a.lang)]") }
                }
                rows.append(Row(combo: name, kind: "keep", lang: member, hit: moved.count, total: total,
                                note: moved.prefix(examples).joined(separator: " ")))

                // typos
                var converted: [String] = [], typoTotal = 0
                for w in Self.words(text) {
                    for t in Self.typos(of: w) {
                        guard let k = Self.keys(for: t, on: id) else { continue }
                        typoTotal += 1
                        if let a = Self.act(resolver.evaluate(keys: k, capsLock: false)).acted { converted.append("\(t)→\(a.text)[\(a.lang)]") }
                    }
                }
                rows.append(Row(combo: name, kind: "typos", lang: member, hit: converted.count, total: typoTotal,
                                note: converted.prefix(examples).joined(separator: " ")))
            }

            // recall and wrong: every language of the combination typed while each other one is active
            for intended in combo {
                let l = Self.lang(intended), id = Self.layoutID(intended)
                guard let text = CombinationCorpus.prose[l] else { continue }
                for active in combo where active != intended {
                    let resolver = NWayResolver(catalog: Catalog(combo, current: active), dict: dict, exceptions: NoExceptions())
                    var right = 0, total = 0, ties = 0, same = 0, sibling = 0
                    var wrong: [String] = [], defaulted: [String] = []
                    for w in Self.words(text) {
                        guard let k = Self.keys(for: w, on: id) else { continue }
                        // A word that renders identically on the active layout needs no conversion.
                        if Catalog(combo, current: active).render(k, layoutID: Self.layoutID(active)) == w { same += 1; continue }
                        total += 1
                        let r = Self.act(resolver.evaluate(keys: k, capsLock: false))
                        if r.tie { ties += 1 }
                        guard let a = r.acted else { continue }
                        // The intended text in a sibling language's layout (a uk/ru tie the preference
                        // settled the other way) is a layout miss the phrase corrects, not a wrong word.
                        // A different text from a tie the preference settled is a *defaulted*
                        // conversion: the app marks it so, and phrase correction owns it. Only a
                        // settled conversion into the wrong text is a wrong word.
                        if a.text == w { if a.lang == l { right += 1 } else { sibling += 1 } }
                        else if r.tie { defaulted.append("\(w)→\(a.text)[\(a.lang)]") }
                        else { wrong.append("\(w)→\(a.text)[\(a.lang)]") }
                    }
                    rows.append(Row(combo: name, kind: "recall", lang: "\(intended)@\(active)", hit: right, total: total,
                                    note: "ties \(ties), right text in a sibling layout \(sibling), identical on both layouts \(same)"))
                    rows.append(Row(combo: name, kind: "wrong", lang: "\(intended)@\(active)", hit: wrong.count, total: total,
                                    note: wrong.prefix(examples).joined(separator: " ")))
                    rows.append(Row(combo: name, kind: "defaulted", lang: "\(intended)@\(active)", hit: defaulted.count,
                                    total: total, note: defaulted.prefix(examples).joined(separator: " ")))
                }
            }

            for r in rows where r.combo == name {
                print(String(format: "combo: %-14@ %-6@ %-9@ %4d/%-5d %6.2f%%  %@", r.combo, r.kind, r.lang,
                             r.hit, r.total, 100 * Double(r.hit) / Double(max(r.total, 1)), r.note))
            }
            print(String(format: "combo: %@ took %.0fs", name, Date().timeIntervalSince(started)))
        }

        if let out = ProcessInfo.processInfo.environment["SWITCHER3W_MEASURE_OUT"] {
            let tsv = (["combo\tkind\tlang\thit\ttotal\tnote"] + rows.map {
                "\($0.combo)\t\($0.kind)\t\($0.lang)\t\($0.hit)\t\($0.total)\t\($0.note)"
            }).joined(separator: "\n")
            try tsv.write(toFile: out, atomically: true, encoding: .utf8)
        }

        // The gate, enforced for combinations of admitted languages only.
        let base = rows.filter { $0.combo == Self.baseline.joined(separator: "+") && $0.kind == "typos" }
        XCTAssertFalse(base.isEmpty, "the en+uk+ru baseline could not be measured on this Mac")
        let bar = base.map { Double($0.hit) / Double(max($0.total, 1)) }.max() ?? 0
        print(String(format: "combo: typo bar (worst language of en+uk+ru) %.2f%%", bar * 100))
        for r in rows {
            let members = r.combo.split(separator: "+").map(String.init)
            guard members.allSatisfy(Self.admitted.contains) else { continue }
            switch r.kind {
            case "keep":  XCTAssertEqual(r.hit, 0, "\(r.combo): correctly typed \(r.lang) moved: \(r.note)")
            case "wrong": XCTAssertEqual(r.hit, 0, "\(r.combo): \(r.lang) converted into the wrong word: \(r.note)")
            case "typos": XCTAssertLessThanOrEqual(Double(r.hit) / Double(max(r.total, 1)), bar + 1e-9,
                                                   "\(r.combo): \(r.lang) typos convert above the bar")
            default: break
            }
        }
    }
}
#endif

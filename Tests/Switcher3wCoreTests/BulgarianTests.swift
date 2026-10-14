import XCTest
@testable import Switcher3wCore

/// Bulgarian on macOS: what changes when it joins English, Ukrainian and Russian. The measured
/// cost per combination lives in `LanguageCombinationTests`; these pin the mechanisms on fakes.
@MainActor
final class BulgarianTests: XCTestCase {

    static let en = "com.apple.keylayout.US"
    static let uk = "com.apple.keylayout.Ukrainian-PC"
    static let bg = "com.apple.keylayout.Bulgarian"
    static let bgPh = "com.apple.keylayout.Bulgarian-Phonetic"

    /// Four keys, rendered per layout. Chosen so each test reads off one row:
    /// row 0 — `xkrt` is gibberish in English, `окан` and `амор` are word-shaped in uk and bg;
    /// row 1 — `reda` on US is `реда` on Bulgarian Phonetic (it transliterates) and noise on
    /// standard Bulgarian.
    static let rows: [String: [String]] = [
        en:   ["xkrt", "reda"],
        uk:   ["окан", "кука"],
        bg:   ["амор", "мама"],
        bgPh: ["хкрт", "реда"],
    ]

    func catalog(_ ids: [String], current: String, flagged: Set<String> = [bgPh]) -> FakeLayoutCatalog {
        let layouts = ids.map { id -> FakeLayoutCatalog.FakeLayout in
            var keys: [UInt16: (Character, Character)] = [:]
            for (row, text) in Self.rows[id]!.enumerated() {
                for (i, ch) in text.enumerated() {
                    keys[UInt16(row * 10 + i)] = (ch, Character(String(ch).uppercased()))
                }
            }
            let lang = id == Self.en ? "en" : (id == Self.uk ? "uk" : "bg")
            return .init(layout: Layout(id: id, lang: lang, transliterates: flagged.contains(id)), keys: keys)
        }
        return FakeLayoutCatalog(layouts: layouts, current: current)
    }

    func keys(row: Int) -> [TypedKey] {
        (0..<4).map { TypedKey(keyCode: UInt16(row * 10 + $0), shift: false, caps: false) }
    }

    func dict(_ words: [String: Set<String>]) -> FakeDictionary {
        let d = FakeDictionary(words)
        d.vowelSets = LanguageProfile.all.mapValues(\.vowels)
        return d
    }

    // MARK: - Ties

    /// Gibberish on the English layout, word-shaped in both Ukrainian and Bulgarian: a Cyrillic
    /// tie, reported like the uk/ru one so the preference decides — and decides for whichever
    /// language the user chose, not for Ukrainian by construction.
    func testRescueTieBetweenBulgarianAndUkrainianGoesToThePreference() {
        let resolver = NWayResolver(catalog: catalog([Self.en, Self.uk, Self.bg], current: Self.en),
                                    dict: dict(["en": [], "uk": [], "bg": []]), exceptions: FakeExceptions())
        guard case .ambiguous(_, let winners) = resolver.evaluate(keys: keys(row: 0), capsLock: false) else {
            return XCTFail("a uk/bg rescue tie should be reported as ambiguous")
        }
        XCTAssertEqual(Set(winners.map(\.lang)), ["bg", "uk"])
        XCTAssertEqual(NWayResolver.resolveAmbiguity(winners: winners, lockedLang: nil, preference: "bg")?.winner.converted, "амор")
        XCTAssertEqual(NWayResolver.resolveAmbiguity(winners: winners, lockedLang: nil, preference: "uk")?.winner.converted, "окан")
        XCTAssertNil(NWayResolver.resolveAmbiguity(winners: winners, lockedLang: nil, preference: "ru"),
                     "a preference outside the tie must not settle it")
    }

    /// A tie across scripts is still a coin toss and keeps.
    func testCrossScriptRescueTieKeeps() {
        XCTAssertFalse(LanguageProfile.shareScript(["en", "bg"]))
        XCTAssertTrue(LanguageProfile.shareScript(["bg", "ru", "uk"]))
        XCTAssertFalse(LanguageProfile.shareScript(["bg", "xx"]), "an unknown language shares nothing")
    }

    // MARK: - Transliterating layouts

    /// `reda` is an English typo; on Bulgarian Phonetic the same keys are the Bulgarian `реда`.
    /// Without the flag it converts — the cost the design measured — and with it, it keeps.
    func testEnglishTypoIsNotConvertedIntoBulgarianPhonetic() {
        let words: [String: Set<String>] = ["en": [], "bg": ["реда"]]
        let unflagged = NWayResolver(catalog: catalog([Self.en, Self.bgPh], current: Self.en, flagged: []),
                                     dict: FakeDictionary(words), exceptions: FakeExceptions())
        guard case .convert(let d) = unflagged.evaluate(keys: keys(row: 1), capsLock: false) else {
            return XCTFail("control: an unflagged phonetic layout is a target")
        }
        XCTAssertEqual(d.converted, "реда")

        let flagged = NWayResolver(catalog: catalog([Self.en, Self.bgPh], current: Self.en),
                                   dict: FakeDictionary(words), exceptions: FakeExceptions())
        guard case .keep = flagged.evaluate(keys: keys(row: 1), capsLock: false) else {
            return XCTFail("a transliterating layout must not be an automatic-fix target")
        }
    }

    /// A word the phonetic layout spells is not handed to anyone else either — even when another
    /// layout also reads the keys as a word. Measured: dropping the layout outright converted
    /// Bulgarian typed on Phonetic into English transliteration for 67 of 195 words.
    func testAWordOnAnExcludedPhoneticLayoutIsNotGivenAway() {
        let resolver = NWayResolver(catalog: catalog([Self.en, Self.bgPh, Self.bg], current: Self.en),
                                    dict: FakeDictionary(["en": [], "bg": ["мама", "реда"]]), exceptions: FakeExceptions())
        guard case .keep(.claimedByTransliteratingLayout) = resolver.evaluate(keys: keys(row: 1), capsLock: false) else {
            return XCTFail("keys that spell a word on Bulgarian Phonetic must be kept")
        }
    }

    /// Typing ON Bulgarian Phonetic is still understood: the current layout is always a candidate,
    /// and a real Bulgarian word typed on it is kept.
    func testTypingOnBulgarianPhoneticIsStillKeptWhenItIsAWord() {
        let resolver = NWayResolver(catalog: catalog([Self.en, Self.bgPh], current: Self.bgPh),
                                    dict: FakeDictionary(["en": [], "bg": ["реда"]]), exceptions: FakeExceptions())
        guard case .keep(.validInCurrent) = resolver.evaluate(keys: keys(row: 1), capsLock: false) else {
            return XCTFail("a Bulgarian word typed on Bulgarian Phonetic must be kept")
        }
    }

    /// Both Bulgarian layouts enabled, typing on Phonetic: what is on screen is the Phonetic
    /// rendering. The standard layout's rendering of the same keys (`мама`) must not answer
    /// "already a word here" for text the user cannot see.
    func testTheCurrentPhoneticLayoutSpeaksForItsLanguage() {
        let resolver = NWayResolver(catalog: catalog([Self.en, Self.bg, Self.bgPh], current: Self.bgPh),
                                    dict: FakeDictionary(["en": ["reda"], "bg": ["мама"]]), exceptions: FakeExceptions())
        guard case .convert(let d) = resolver.evaluate(keys: keys(row: 1), capsLock: false) else {
            return XCTFail("`реда` is not a word here and `reda` is English: expected a conversion")
        }
        XCTAssertEqual(d.lang, "en")
    }

    /// With both Bulgarian layouts enabled and English current, the standard layout is the target.
    func testStandardBulgarianIsTheTargetWhenBothAreEnabled() {
        let resolver = NWayResolver(catalog: catalog([Self.en, Self.bgPh, Self.bg], current: Self.en),
                                    dict: FakeDictionary(["en": [], "bg": ["мама"]]), exceptions: FakeExceptions())
        guard case .convert(let d) = resolver.evaluate(keys: keys(row: 1), capsLock: false) else {
            return XCTFail("expected a conversion to standard Bulgarian")
        }
        XCTAssertEqual(d.targetLayoutID, Self.bg)
        XCTAssertEqual(d.converted, "мама")
    }

    /// The manual trigger is an explicit request and still reaches the phonetic layout.
    func testManualTriggerStillReachesBulgarianPhonetic() {
        let resolver = NWayResolver(catalog: catalog([Self.en, Self.bgPh], current: Self.en),
                                    dict: FakeDictionary(["en": [], "bg": ["реда"]]), exceptions: FakeExceptions())
        let plan = resolver.manualPlan(keys: keys(row: 1), capsLock: false, ambiguousLang: "uk")
        XCTAssertEqual(plan?.candidates.map(\.targetLayoutID), [Self.bgPh])
    }

    // MARK: - Per-language knowledge

    /// A supported language has every piece of knowledge, or it fails open somewhere.
    func testEveryProfileIsComplete() {
        for (code, p) in LanguageProfile.all {
            XCTAssertEqual(p.code, code)
            XCTAssertFalse(p.vowels.isEmpty, "\(code) has no vowels: the rescue is off for it")
            XCTAssertFalse(p.canary.word.isEmpty, "\(code) has no canary")
            XCTAssertTrue(ShortWords.covers(code), "\(code) has no short-word list")
        }
    }

    /// `ъ` is a vowel in Bulgarian, and the short words that depend on it are words.
    func testBulgarianShapeAndShortWords() {
        let v = LanguageProfile.of("bg")!.vowels
        for w in ["път", "съм", "към", "къща", "ъгъл"] {
            XCTAssertTrue(WordShape.isPlausible(w, vowels: v, lang: "bg"), w)
        }
        for w in ["ще", "е", "са", "го", "му", "ѝ", "съм", "път"] {
            XCTAssertTrue(ShortWords.admits(w, lang: "bg"), w)
        }
    }

    /// Real English contractions are words; what Bulgarian `ч` on the apostrophe key renders as
    /// is not, whatever the spell checker says about its pieces.
    func testEnglishContractionsAreJudgedByGrammar() {
        for w in ["don't", "can't", "it's", "John's", "I'm", "you're", "we'll", "they've", "I'd",
                  "that's", "o'clock", "y'all", "isn\u{2019}t"] {
            XCTAssertTrue(Contractions.admits(w, lang: "en"), w)
        }
        for w in ["fr'd", "w'go", "l'ed", "em'e", "me''e", "dir'd", "go't", "car'm"] {
            XCTAssertFalse(Contractions.admits(w, lang: "en"), w)
        }
        XCTAssertTrue(Contractions.admits("п'ять", lang: "uk"), "only English is judged")
        XCTAssertTrue(Contractions.admits("hello", lang: "en"))
    }

    #if canImport(AppKit)
    /// The canaries against the dictionary this Mac actually has: each word accepted, each mash
    /// rejected. A canary the healthy dictionary fails would quarantine its language forever.
    func testCanariesHoldAgainstTheRealSpellChecker() throws {
        let real = RealDictionary()
        for (code, p) in LanguageProfile.all.sorted(by: { $0.key < $1.key }) {
            guard real.isAvailable(code) else { print("canary: skip \(code) — no system dictionary"); continue }
            XCTAssertTrue(real.isValidWord(p.canary.word, lang: code), "\(code) rejects its canary \(p.canary.word)")
            XCTAssertFalse(real.isValidWord(p.canary.mash, lang: code), "\(code) accepts its mash \(p.canary.mash)")
        }
        // The Bulgarian canary must be Bulgarian only, or a dictionary answering for the wrong
        // language would pass it.
        if real.isAvailable("ru") { XCTAssertFalse(real.isValidWord("здравей", lang: "ru")) }
        if real.isAvailable("uk") { XCTAssertFalse(real.isValidWord("здравей", lang: "uk")) }
    }
    #endif
}

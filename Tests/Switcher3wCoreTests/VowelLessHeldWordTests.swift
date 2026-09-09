import XCTest
@testable import Switcher3wCore

/// The vowel-less held-word rule, on the fake dictionary: what it fires on and what it waits for.
/// Its precision against real abbreviations is measured separately in
/// `VowelLessHeldWordMeasurement` with the system dictionaries.
@MainActor
final class VowelLessHeldWordTests: XCTestCase {

    private lazy var catalog = Fixture.catalog(current: Fixture.uk)
    private lazy var dict: FakeDictionary = {
        let d = FakeDictionary([
            "en": ["on", "no", "new", "hi"],
            "uk": ["так", "не"],
            "ru": ["так", "не"],
        ])
        d.vowelSets = ["en": "aeiouy", "uk": "аеєиіїоуюя", "ru": "аеёиоуыэюя"]
        return d
    }()
    private lazy var resolver = NWayResolver(catalog: catalog, dict: dict, exceptions: FakeExceptions())

    /// Would the rule act on this held word, were it enabled? The predicate is what is under test
    /// here; whether it is switched on is the measurement's business.
    private func settlesAlone(_ outcome: NWayResolver.Outcome, typedLang: String) -> Bool {
        guard case .held(let original, let winners) = outcome else { return false }
        return NWayResolver.heldWordSettlesAlone(original: original, winners: winners,
                                                 typedVowels: dict.vowels(typedLang), enabled: true)
    }

    func testTheRuleIsSwitchedOffUntilTheMeasurementAdmitsIt() {
        // Documented on the constant: 18/76 legitimate abbreviations converted on the real
        // dictionaries. The predicate returns false for everything while the switch is off.
        XCTAssertFalse(NWayResolver.vowelLessHeldWordEnabled)
        let o = resolver.evaluate(keys: Fixture.keysForCyrillic("щт", lang: "uk"), capsLock: false)
        guard case .held(let original, let winners) = o else { return XCTFail("expected held") }
        XCTAssertFalse(NWayResolver.heldWordSettlesAlone(original: original, winners: winners,
                                                         typedVowels: dict.vowels("uk")))
    }

    func testASameTextSiblingHitIsNotNoise() {
        // "хз" typed on uk, listed only by the ru dictionary: the same letters, so nothing says it
        // landed in the wrong language — the rule must not flip the layout on it.
        dict.words["ru"]?.insert("хз")
        let o = resolver.evaluate(keys: Fixture.keysForCyrillic("хз", lang: "uk"), capsLock: false)
        guard case .held = o else { return XCTFail("expected held, got \(o)") }
        XCTAssertFalse(settlesAlone(o, typedLang: "uk"))
    }

    func testAVowelLessHeldWordSettlesAtOnce() {
        // "on" and "no" typed on the Ukrainian layout are "щт" and "тщ" — no vowel, keyboard noise.
        for word in ["щт", "тщ"] {
            let o = resolver.evaluate(keys: Fixture.keysForCyrillic(word, lang: "uk"), capsLock: false)
            XCTAssertTrue(settlesAlone(o, typedLang: "uk"), "\(word) should settle on its own")
        }
    }

    func testAHeldWordWithAVowelStillWaitsForThePhrase() {
        // "new" on the Ukrainian layout is "туц" — held, but it has a vowel, so it waits as before.
        let o = resolver.evaluate(keys: Fixture.keysForCyrillic("туц", lang: "uk"), capsLock: false)
        guard case .held = o else { return XCTFail("expected held, got \(o)") }
        XCTAssertFalse(settlesAlone(o, typedLang: "uk"))
    }

    func testAnAmbiguousVowelLessWordDoesNotSettle() {
        // "так" typed on US is "nfr": no English vowel, but it reads as uk AND ru — two readings say
        // nothing about which language the phrase is in, so it waits.
        catalog.current = Fixture.en
        let o = resolver.evaluate(keys: Fixture.keys("nfr"), capsLock: false)
        guard case .held(_, let winners) = o else { return XCTFail("expected held, got \(o)") }
        XCTAssertEqual(winners.count, 2)
        XCTAssertFalse(settlesAlone(o, typedLang: "en"))
    }

    func testWithoutAVowelSetTheRuleIsOff() {
        XCTAssertTrue(WordShape.hasVowel("щт", vowels: ""), "an unknown language cannot be called vowel-less")
    }
}

// The measurement against the REAL system dictionaries — the only part tied to Apple's frameworks,
// guarded like `DictionaryQualityTests` so the rest of the suite stays platform-independent.
#if canImport(AppKit)
import AppKit

/// Counts the legitimate vowel-less abbreviations in `VowelLessFixture` that the rule would convert.
/// The rule is admitted at zero and at nothing else: it trades precision for recall on the shortest
/// words the app ever touches, and a rule like that is measured before it is allowed to act.
@MainActor
final class VowelLessHeldWordMeasurement: XCTestCase {

    private struct SystemSpellChecker: DictionaryValidating {
        let checker = NSSpellChecker.shared
        func isAvailable(_ lang: String) -> Bool {
            checker.availableLanguages.contains { String($0.prefix(2)) == String(lang.prefix(2)) }
        }
        func isValidWord(_ word: String, lang: String) -> Bool {
            let range = checker.checkSpelling(of: word, startingAt: 0, language: lang,
                                              wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
            return range.location == NSNotFound
        }
        func vowels(_ lang: String) -> String {
            switch String(lang.prefix(2)) {
            case "en": return "aeiouy"
            case "uk": return "аеєиіїоуюя"
            case "ru": return "аеёиоуыэюя"
            default:   return ""
            }
        }
        func warmUp(_ lang: String) { _ = isValidWord("warmup", lang: lang) }
    }

    func testTheRuleConvertsNoLegitimateAbbreviation() throws {
        let dict = SystemSpellChecker()
        let catalog = Fixture.catalog()
        let resolver = NWayResolver(catalog: catalog, dict: dict, exceptions: FakeExceptions())
        var measured = 0
        var wouldConvert: [String] = []

        for (lang, tokens) in VowelLessFixture.tokens.sorted(by: { $0.key < $1.key }) {
            guard dict.isAvailable(lang) else { continue }
            dict.warmUp(lang)
            catalog.current = lang == "en" ? Fixture.en : (lang == "uk" ? Fixture.uk : Fixture.ru)
            for token in tokens {
                let keys = lang == "en" ? Fixture.keys(token) : Fixture.keysForCyrillic(token, lang: lang)
                measured += 1
                guard case .held(let original, let winners) = resolver.evaluate(keys: keys, capsLock: false),
                      NWayResolver.heldWordSettlesAlone(original: original, winners: winners,
                                                        typedVowels: dict.vowels(lang), enabled: true)
                else { continue }
                wouldConvert.append("\(lang):\(token)→\(winners[0].converted) [\(winners[0].lang)]")
            }
        }
        try XCTSkipIf(measured == 0, "no system dictionary installed for any fixture language")
        // Always printed, so the number is re-read on every run. History on this port:
        //   2026-09-08  8/76 — with the same-text exclusion; 18/76 without it
        //   2026-09-09  2/76 — after the short-word allow-list removed the junk winners
        // What remains is `см` (centimetre) reading as `cv`, which is on the English list because
        // people do type CV. The bar for switching the rule on is zero, and tuning the list to
        // reach it would be tuning the evidence, so the rule stays off. The Windows port measures
        // 0/76 against Hunspell; both must be clean before the constant moves.
        print("vowel-less rule: \(wouldConvert.count)/\(measured) legitimate abbreviations would convert: \(wouldConvert)")
        if NWayResolver.vowelLessHeldWordEnabled {
            XCTAssertEqual(wouldConvert.count, 0,
                           "the vowel-less held-word rule converts real abbreviations: \(wouldConvert)")
        } else {
            XCTAssertLessThanOrEqual(wouldConvert.count, 2,
                "this port measured 2/76 on 2026-09-09; a higher number means something regressed: \(wouldConvert)")
        }
    }
}
#endif

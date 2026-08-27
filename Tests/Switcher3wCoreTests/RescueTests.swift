import XCTest
@testable import Switcher3wCore

/// The gibberish rescue, on deterministic fakes: every branch of `NWayResolver.rescue` and its
/// interaction with the gates around it. The measured behavior against real dictionaries lives in
/// `RescueQualityTests`; these tests pin the mechanism.
@MainActor
final class RescueTests: XCTestCase {

    private func makeResolver(current: String = Fixture.en,
                              enWords: Set<String> = [],
                              vowelled: Bool = true,
                              enAlphabet: String = "") -> NWayResolver {
        let dict = FakeDictionary(["en": enWords, "uk": [], "ru": []])
        if vowelled {
            dict.vowelSets = ["en": "aeiouy", "uk": "аеєиіїоуюя", "ru": "аеёиоуыэюя"]
        }
        if !enAlphabet.isEmpty { dict.alphabets["en"] = enAlphabet }
        return NWayResolver(catalog: Fixture.catalog(current: current),
                            dict: dict, exceptions: FakeExceptions())
    }

    /// `fgrf` — gibberish in English, `апка` in both Cyrillic languages: the ru/uk pair is
    /// reported as ambiguous, exactly like a shared dictionary word, so the caller's preference
    /// setting (and its "off") keeps its authority.
    func testLatinGibberishWithCyrillicShapeIsAmbiguousRescue() {
        let outcome = makeResolver().evaluate(keys: Fixture.keys("fgrf"), capsLock: false)
        guard case .ambiguous(let original, let winners) = outcome else {
            return XCTFail("expected .ambiguous, got \(outcome)")
        }
        XCTAssertEqual(original, "fgrf")
        XCTAssertEqual(Set(winners.map(\.lang)), ["ru", "uk"])
        XCTAssertEqual(winners.first(where: { $0.lang == "uk" })?.converted, "апка")
    }

    /// `лншм` typed in the Russian layout — gibberish there and in Ukrainian, `kyiv` in English:
    /// a unique plausible candidate converts outright, as `.rescued` (defaulted, not locked).
    func testCyrillicGibberishWithUniqueEnglishShapeIsRescued() {
        let resolver = makeResolver(current: Fixture.ru)
        let outcome = resolver.evaluate(keys: Fixture.keysForCyrillic("лншм", lang: "ru"),
                                        capsLock: false)
        guard case .rescued(let d) = outcome else {
            return XCTFail("expected .rescued, got \(outcome)")
        }
        XCTAssertEqual(d.lang, "en")
        XCTAssertEqual(d.converted, "kyiv")
        XCTAssertEqual(d.original, "лншм")
    }

    /// A token that is word-shaped in the language it was typed in is not the rescue's business,
    /// however unknown it is — `kyiv` typed in the English layout stays.
    func testPlausibleInTypedLanguageKeeps() {
        let outcome = makeResolver().evaluate(keys: Fixture.keys("kyiv"), capsLock: false)
        guard case .keep(.notAWordAnywhere) = outcome else {
            return XCTFail("expected keep, got \(outcome)")
        }
    }

    /// Gibberish on every side stays: `gkml` has no vowel in English and renders to the equally
    /// vowel-less `плдь` in Cyrillic. No plausible target → no rescue.
    func testGibberishEverywhereKeeps() {
        let outcome = makeResolver().evaluate(keys: Fixture.keys("gkml"), capsLock: false)
        guard case .keep(.notAWordAnywhere) = outcome else {
            return XCTFail("expected keep, got \(outcome)")
        }
    }

    /// The soft gates outrank the rescue: an all-caps token is an acronym whatever its renders
    /// look like.
    func testAllCapsIsVetoedBeforeRescue() {
        let outcome = makeResolver().evaluate(keys: Fixture.keys("FGRF"), capsLock: false)
        guard case .keep(.notAWordAnywhere) = outcome else {
            return XCTFail("expected keep, got \(outcome)")
        }
    }

    /// Below the floor the shape signals mean nothing (`msg`, `хз` territory): keep.
    func testBelowFloorKeeps() {
        let outcome = makeResolver().evaluate(keys: Fixture.keys("fgf"), capsLock: false)
        guard case .keep(.notAWordAnywhere) = outcome else {
            return XCTFail("expected keep, got \(outcome)")
        }
    }

    /// A validator that does not name the language's vowels cannot call anything gibberish:
    /// the rescue stays off entirely (fail-open, like the near-miss alphabet).
    func testNoVowelSetsDisablesRescue() {
        let outcome = makeResolver(vowelled: false)
            .evaluate(keys: Fixture.keys("fgrf"), capsLock: false)
        guard case .keep(.notAWordAnywhere) = outcome else {
            return XCTFail("expected keep, got \(outcome)")
        }
    }

    /// The typo guard outranks the rescue: `ftyf` is one substitution from the (fake) English word
    /// `ftya`, so a fumbled key stays the simpler story and nothing converts.
    func testNearMissOfTypedLanguageVetoesRescue() {
        let resolver = makeResolver(enWords: ["ftya"],
                                    enAlphabet: "abcdefghijklmnopqrstuvwxyz")
        let outcome = resolver.evaluate(keys: Fixture.keys("ftyf"), capsLock: false)
        guard case .keep(.looksLikeATypo) = outcome else {
            return XCTFail("expected keep(looksLikeATypo), got \(outcome)")
        }
    }

    /// The manual cycle promotes a rescued reading to the front, so one trigger tap on `лншм`
    /// offers `kyiv` first.
    func testManualPlanPromotesRescuedCandidate() {
        let resolver = makeResolver(current: Fixture.ru)
        let plan = resolver.manualPlan(keys: Fixture.keysForCyrillic("лншм", lang: "ru"),
                                       capsLock: false, ambiguousLang: "uk")
        XCTAssertEqual(plan?.candidates.first?.converted, "kyiv")
    }
}

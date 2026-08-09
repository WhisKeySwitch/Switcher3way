import XCTest
@testable import Switcher3wCore

/// The manual trigger's candidate plan. Unlike the auto path this is an EXPLICIT user action, so
/// it offers every layout that renders differently — but it still puts the answer auto-fix would
/// have given first, so one tap is usually enough.
@MainActor
final class ManualPlanTests: XCTestCase {

    private lazy var catalog = Fixture.catalog(current: Fixture.en)
    private lazy var dict = FakeDictionary([
        "en": ["hello"],
        // "город" is valid in BOTH: a vegetable garden in Ukrainian, a city in Russian.
        "uk": ["привіт", "добре", "місто", "город"],
        "ru": ["привет", "добре", "город", "хорошо"],
    ])
    private lazy var exceptions = FakeExceptions()
    private lazy var resolver = NWayResolver(catalog: catalog, dict: dict, exceptions: exceptions)
    private lazy var reference = Fixture.catalog(current: Fixture.en)

    private func plan(_ latin: String, ambiguousLang: String = "uk", caps: Bool = false)
        -> (original: String, originalLayoutID: String, candidates: [NWayResolver.ManualCandidate])? {
        resolver.manualPlan(keys: Fixture.keys(latin, caps: caps), capsLock: caps,
                            ambiguousLang: ambiguousLang)
    }

    func testOffersEveryLayoutThatRendersDifferently() {
        // uk and ru render these keystrokes differently from en and from each other ("і" vs "ы").
        guard let p = plan(latinFor("місто", lang: "uk")) else { return XCTFail("expected a plan") }
        XCTAssertEqual(Set(p.candidates.map(\.targetLayoutID)), [Fixture.uk, Fixture.ru])
        XCTAssertEqual(p.originalLayoutID, Fixture.en)
    }

    func testConvertsEvenWhenAutoWouldDecline() {
        // "hello" is a valid English word — auto keeps it, but an explicit trigger still cycles.
        guard let p = plan("hello") else {
            return XCTFail("the trigger must act even where auto declines")
        }
        XCTAssertFalse(p.candidates.isEmpty)
    }

    func testDictionaryWinnerIsOfferedFirst() {
        // "місто" is uk-only, so one tap should land on Ukrainian rather than the OS order.
        guard let p = plan(latinFor("місто", lang: "uk")) else { return XCTFail("expected a plan") }
        XCTAssertEqual(p.candidates.first?.targetLayoutID, Fixture.uk)
        XCTAssertEqual(p.candidates.first?.converted, "місто")
    }

    func testAmbiguousWordFollowsThePreferenceEvenWhenRendersCollapse() {
        // An "ambiguous" word is by definition one whose render is valid in both uk and ru — which
        // means the two layouts render it identically and the dedup keeps only one entry. The
        // preference must still decide which LAYOUT that entry carries; before the fix it could
        // not move anything at all, so the setting did nothing on this path.
        for (preference, expected) in [("uk", Fixture.uk), ("ru", Fixture.ru)] {
            guard let p = plan(latinFor("добре", lang: "uk"), ambiguousLang: preference) else {
                return XCTFail("expected a plan")
            }
            XCTAssertEqual(p.candidates.first?.targetLayoutID, expected,
                           "preference '\(preference)' must select the layout")
            XCTAssertEqual(p.candidates.first?.converted, "добре", "the text is the same either way")
            XCTAssertEqual(p.candidates.count, 1,
                           "still ONE step — a step showing identical text would look like a no-op")
        }
    }

    func testAmbiguityPreferenceOffFallsBackToRotationOrder() {
        // "Do not convert" means "leave ambiguous words alone" for auto-fix. The trigger converts
        // them by design (explicit request), so here it reads as "no preference between uk and ru"
        // and the rotation order stands — unchanged behavior.
        guard let p = plan(latinFor("добре", lang: "uk"), ambiguousLang: "off") else {
            return XCTFail("expected a plan")
        }
        XCTAssertEqual(p.candidates.first?.targetLayoutID, Fixture.uk,
                       "uk follows en in the fixture's rotation order")
    }

    func testPreferenceCannotDragAWordIntoALanguageThatDoesNotValidateIt() {
        // "місто" is Ukrainian only. A preference of ru must not pull it into the Russian layout —
        // the preference only chooses AMONG the languages that actually validate the render.
        guard let p = plan(latinFor("місто", lang: "uk"), ambiguousLang: "ru") else {
            return XCTFail("expected a plan")
        }
        XCTAssertEqual(p.candidates.first?.targetLayoutID, Fixture.uk)
        XCTAssertEqual(p.candidates.first?.converted, "місто")
    }

    func testNoDictionaryEvidenceLeavesRotationOrder() {
        // Gibberish: no language validates it, so nothing is promoted and the cycle is whatever
        // rotation order gives — unchanged behavior.
        guard let p = plan("qwzx") else { return XCTFail("expected a plan") }
        XCTAssertEqual(p.candidates.first?.targetLayoutID, Fixture.uk)
    }

    func testPreferencePromotesWhenBothLayoutsRenderDifferently() {
        // Where the two renders DO differ, both are real candidates and the preference decides.
        // "місто"/"мысто" differ on the і/ы key, so this exercises the promotion the case above
        // cannot reach.
        dict.words["ru"]?.insert("мисто")
        let latin = latinFor("місто", lang: "uk")
        guard let uk = plan(latin, ambiguousLang: "uk") else { return XCTFail("expected a plan") }
        XCTAssertEqual(uk.candidates.first?.targetLayoutID, Fixture.uk)
        XCTAssertEqual(uk.candidates.count, 2, "differing renders stay separate candidates")
    }

    func testCollapsedRenderCarriesTheDictionaryWinnersLayout() {
        // "хорошо" is Russian only (Ukrainian says добре/гарно) and contains no letter the two
        // layouts place differently (no і/ї/є/ы/э/ъ), so uk and ru render it identically and the
        // dedup keeps only the first in rotation order. The surviving candidate must nonetheless
        // carry the RUSSIAN layout — otherwise the trigger produces the right word and leaves the
        // user typing Ukrainian, which is what it used to do for any word of shared letters.
        //
        // Independent of the ambiguity preference: this word has one winner, not two.
        for preference in ["uk", "ru", "off"] {
            guard let p = plan(latinFor("хорошо", lang: "ru"), ambiguousLang: preference) else {
                return XCTFail("expected a plan")
            }
            XCTAssertEqual(p.candidates.first?.converted, "хорошо")
            XCTAssertEqual(p.candidates.first?.targetLayoutID, Fixture.ru,
                           "the dictionary winner's layout, not the collapsed survivor's")
            XCTAssertEqual(p.candidates.count, 1)
        }
    }

    func testNoPlanForRemoteForwardedCharacters() {
        // keyCode 0 + a character: every layout renders the same, so cycling is meaningless.
        let keys = [TypedKey(keyCode: 0, shift: false, caps: false, char: "a")]
        XCTAssertNil(resolver.manualPlan(keys: keys, capsLock: false, ambiguousLang: "uk"))
    }

    func testNoPlanForEmptyInput() {
        XCTAssertNil(resolver.manualPlan(keys: [], capsLock: false, ambiguousLang: "uk"))
    }

    func testNoPlanWhenOnlyOneLayoutIsInstalled() {
        let single = Fixture.catalog(current: Fixture.en, langs: ["en"])
        let r = NWayResolver(catalog: single, dict: dict, exceptions: exceptions)
        XCTAssertNil(r.manualPlan(keys: Fixture.keys("hello"), capsLock: false, ambiguousLang: "uk"))
    }

    func testIdenticalRendersAreOfferedOnce() {
        // "город" renders identically in uk and ru (no і/ы in it), so only one candidate survives.
        // (It is also a real word in both languages — a vegetable garden vs a city.)
        guard let p = plan(latinFor("город", lang: "ru")) else { return XCTFail("expected a plan") }
        XCTAssertEqual(p.candidates.count, 1, "duplicate renders must be collapsed")
    }

    private func latinFor(_ word: String, lang: String) -> String {
        let target = lang == "uk" ? Fixture.uk : Fixture.ru
        let alphabet = Fixture.keys("abcdefghijklmnopqrstuvwxyz',;,.[]")
        var out = ""
        for ch in word {
            for k in alphabet where reference.render([k], layoutID: target) == String(ch) {
                out.append(reference.render([k], layoutID: Fixture.en) ?? "")
                break
            }
        }
        return out
    }
}

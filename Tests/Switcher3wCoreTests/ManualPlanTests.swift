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

    func testAmbiguousWordIgnoresThePreferenceWhenRendersCollapse() {
        // KNOWN LIMITATION, pinned here deliberately.
        //
        // An "ambiguous" word is by definition one whose RENDER is valid in both uk and ru — which
        // means the two layouts render it identically. The candidate loop dedups by rendered
        // string, so only the first of them (OS order) ever becomes a candidate, and the promotion
        // step can then only re-promote that same entry. The result: on the manual trigger an
        // ambiguous word always lands on whichever of uk/ru comes first in the OS order, whatever
        // the ambiguity preference says.
        //
        // The auto path is unaffected — it picks from `evaluate`'s winners by language directly,
        // before any dedup. The manual path's own comment claims the preference "takes that spot",
        // which overstates what the code does.
        //
        // Left as behavior: this change extracts the resolver, it does not redesign the cycle.
        for preference in ["uk", "ru", "off"] {
            guard let p = plan(latinFor("добре", lang: "uk"), ambiguousLang: preference) else {
                return XCTFail("expected a plan")
            }
            XCTAssertEqual(p.candidates.first?.targetLayoutID, Fixture.uk,
                           "preference '\(preference)' cannot move a collapsed candidate")
            XCTAssertEqual(p.candidates.count, 1, "identical uk/ru renders collapse to one candidate")
        }
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

    func testCollapsedRenderKeepsTheFirstLayoutEvenForAnUnambiguousWinner() {
        // The same collapse as above, and this is its wider consequence. "хорошо" is Russian only
        // (Ukrainian says добре/гарно), so the dictionary winner is unambiguously ru — but the
        // word contains no letter the two layouts place differently (no і/ї/є/ы/э/ъ), so uk and ru
        // render it identically and only the first in OS order survives dedup. The candidate the
        // user gets carries the UK layout.
        //
        // So the text is right and the layout is not: the trigger leaves the user in Ukrainian
        // while they are typing Russian. This affects any Cyrillic word built purely from the
        // letters the two layouts share — not a rare shape.
        guard let off = plan(latinFor("хорошо", lang: "ru"), ambiguousLang: "off") else {
            return XCTFail("expected a plan")
        }
        XCTAssertEqual(off.candidates.first?.converted, "хорошо", "the text is correct")
        XCTAssertEqual(off.candidates.first?.targetLayoutID, Fixture.uk,
                       "…but the layout is the collapsed survivor, not the dictionary winner")
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

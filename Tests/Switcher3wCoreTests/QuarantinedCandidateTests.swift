import XCTest
@testable import Switcher3wCore

/// A quarantined dictionary takes its VERDICT out of the decision, not its language. Before this,
/// `isAvailable == false` dropped the language from the candidate set, the machine looked
/// two-language for the cooldown, and a Ukrainian word typed on the English layout converted into
/// Russian unopposed — the field log has `Вітаю` → `Вытаю` and `Привіт!` → `Привыт!` six times over
/// eight days, every one inside a uk quarantine window, while the ambiguity preference said uk.
@MainActor
final class QuarantinedCandidateTests: XCTestCase {

    private var dict: FakeDictionary!
    private var sentinel: DictionarySentinel!

    override func setUp() {
        super.setUp()
        // `привіт` is deliberately missing from uk: the sentinel's word canary fails and uk sits in
        // quarantine from the first probe. ru and en carry no canary and stay trusted.
        dict = FakeDictionary([
            "en": ["hello", "myrrh", "natalie"],
            "uk": ["тебе", "вони"],
            "ru": ["тебе", "привет", "вони"],
        ])
        dict.vowelSets = ["en": "aeiouy", "uk": "аеєиіїоуюя", "ru": "аеёиоуыэюя"]
        sentinel = DictionarySentinel(wrapping: dict,
                                      canaries: ["uk": .init(word: "привіт", mash: "нзукжз")])
    }

    private func resolver(current: String) -> NWayResolver {
        NWayResolver(catalog: Fixture.catalog(current: current), dict: sentinel, exceptions: FakeExceptions())
    }

    func testQuarantineIsReportedAsSuchNotAsMissing() {
        XCTAssertFalse(sentinel.isAvailable("uk"))
        XCTAssertTrue(sentinel.isQuarantined("uk"), "installed but distrusted")
        XCTAssertFalse(sentinel.isQuarantined("ru"), "ru has no canary and is trusted")
        XCTAssertFalse(sentinel.isQuarantined("bg"), "not installed is not the same as quarantined")
    }

    /// The field case. `nt,t` is тебе in both uk and ru; with uk unable to answer, ru must not win
    /// by default — with a healthy uk this would have been an ambiguity for the preference setting.
    func testSharedWordIsNotHandedToTheSiblingDuringQuarantine() {
        let outcome = resolver(current: Fixture.en).evaluate(keys: Fixture.keys("nt,t"), capsLock: false)
        guard case .keep(let reason) = outcome else {
            return XCTFail("converted while uk could not answer: \(outcome)")
        }
        XCTAssertEqual(reason, .dictionaryUntrusted)
    }

    /// The phrase is evidence the quarantine does not touch: a run of Russian already settled it.
    func testPhraseLockOnTheWinnerStillConverts() {
        let outcome = resolver(current: Fixture.en).evaluate(keys: Fixture.keys("nt,t"), capsLock: false,
                                                             phraseLang: "ru")
        guard case .convert(let d) = outcome else { return XCTFail("phrase-backed ru refused: \(outcome)") }
        XCTAssertEqual(d.lang, "ru")
        XCTAssertEqual(d.converted, "тебе")
    }

    /// `Dsnf.` is Вітаю in uk and Вытаю in ru; neither dictionary knows it. The rescue judges shape,
    /// not verdicts, so a quarantined uk is a full candidate there — and the outcome is the uk/ru
    /// ambiguity the preference exists for, not a Russian misspelling of a Ukrainian greeting.
    func testUnknownWordRescuesAsAmbiguityNotAsRussian() {
        let outcome = resolver(current: Fixture.en).evaluate(keys: Fixture.keys("Dsnf."), capsLock: false)
        guard case .ambiguous(_, let winners) = outcome else {
            return XCTFail("expected a uk/ru ambiguity, got \(outcome)")
        }
        XCTAssertEqual(Set(winners.map(\.lang)), ["ru", "uk"])
        XCTAssertEqual(winners.first { $0.lang == "uk" }?.converted, "Вітаю")
    }

    /// Typing IN the quarantined language: whether the word is real cannot be known, and "not a word
    /// here" is the premise of every conversion. Reported as the dictionary's problem, not as the
    /// layout having no language.
    func testTypingInTheQuarantinedLanguageKeeps() {
        let outcome = resolver(current: Fixture.uk).evaluate(keys: Fixture.keysForCyrillic("тебе", lang: "uk"),
                                                             capsLock: false)
        guard case .keep(let reason) = outcome else { return XCTFail("moved uk text: \(outcome)") }
        XCTAssertEqual(reason, .dictionaryUntrusted)
    }

    /// A quarantined language only contests what it could plausibly have claimed. `myrrh` on the
    /// Russian layout renders `ьнккр` in uk — no vowel, not a word shape — so English wins as usual.
    func testShapelessQuarantinedRenderingDoesNotContest() {
        let outcome = resolver(current: Fixture.ru).evaluate(keys: Fixture.keys("myrrh"), capsLock: false)
        guard case .convert(let d) = outcome else { return XCTFail("en refused over a shapeless uk render: \(outcome)") }
        XCTAssertEqual(d.lang, "en")
    }

    /// Nothing changes for a healthy dictionary: the same word is the ordinary uk/ru ambiguity.
    func testHealthyDictionaryIsUntouched() {
        dict.words["uk"]?.insert("привіт")
        let outcome = resolver(current: Fixture.en).evaluate(keys: Fixture.keys("nt,t"), capsLock: false)
        guard case .ambiguous(_, let winners) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(Set(winners.map(\.lang)), ["ru", "uk"])
    }
}

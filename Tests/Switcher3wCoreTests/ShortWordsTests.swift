import XCTest
@testable import Switcher3wCore

/// The short-word allow-list: the dictionary's verdict on a one-, two- or three-letter word is only
/// believed when the word is one the language's speakers actually type.
///
/// The reported defect: "the app keeps converting це into wt". It converted nothing — the user typed
/// Ukrainian with the English layout active, `це` landed as `wt`, and because `NSSpellChecker` calls
/// `wt` an English word the resolver reported "already a word in this layout's language" and left it
/// there. Eight times in thirteen days, plus `ye` for ну five times.
@MainActor
final class ShortWordsTests: XCTestCase {

    // MARK: - the list itself

    func testTheDictionaryNoiseThatCausedTheDefectIsNotAdmitted() {
        // Every one of these is in the macOS English dictionary and none of them is a word anyone
        // types meaning itself. Each blocked a real Ukrainian word in the field log.
        for junk in ["wt", "ye", "pf", "lys"] {
            XCTAssertFalse(ShortWords.admits(junk, lang: "en"), "'\(junk)' must not vouch for itself")
        }
    }

    func testRealShortWordsAreAdmitted() {
        for w in ["a", "i", "in", "of", "the", "and", "you", "app", "try"] {
            XCTAssertTrue(ShortWords.admits(w, lang: "en"), w)
        }
        // Abbreviations typed as themselves every day. A structural rule cannot tell these from
        // noise — `src` renders as the real Ukrainian word `ікс` — so they are named, not inferred.
        for w in ["api", "npm", "src", "pwd", "msg", "sql", "id", "os"] {
            XCTAssertTrue(ShortWords.admits(w, lang: "en"), w)
        }
        // The words a mistake on the Cyrillic side would convert away.
        for w in ["це", "за", "зі", "між", "дні", "не", "на", "як", "що", "ще", "я", "ми"] {
            XCTAssertTrue(ShortWords.admits(w, lang: "uk"), w)
        }
        for w in ["это", "что", "как", "уже", "не", "на", "мы", "ты", "его"] {
            XCTAssertTrue(ShortWords.admits(w, lang: "ru"), w)
        }
    }

    func testTheJunkRenderingsOfEnglishWordsAreNotAdmittedEither() {
        // The mirror of the defect: typing English on a Cyrillic layout. `the` lands as `еру`, which
        // the Ukrainian dictionary accepts — so without this the fix would fail in that direction too.
        for junk in ["еру", "шт", "ща", "цу", "иге", "ин", "фт", "гл"] {
            XCTAssertFalse(ShortWords.admits(junk, lang: "uk") && ShortWords.admits(junk, lang: "ru"),
                           "'\(junk)' must not vouch for itself in both Cyrillic languages")
        }
    }

    func testTheListIsIgnoredFromFourLettersUp() {
        // Long enough to speak for itself: the list must not become a second dictionary.
        for w in ["хорошо", "keyboard", "квартира", "wxyz", "фівапр"] {
            XCTAssertTrue(ShortWords.admits(w, lang: "uk"), w)
            XCTAssertTrue(ShortWords.admits(w, lang: "en"), w)
        }
    }

    func testAnUnlistedLanguageFallsThroughToTheDictionary() {
        // Fail open, like the near-miss alphabet and the rescue's vowels: a language with no list
        // behaves as it did before, rather than having every short word silently vetoed.
        XCTAssertFalse(ShortWords.covers("bg"))
        XCTAssertTrue(ShortWords.admits("що", lang: "bg"))
    }

    // MARK: - end to end, through the resolver

    private lazy var catalog = Fixture.catalog(current: Fixture.en)
    private lazy var dict: FakeDictionary = {
        // A dictionary as permissive about short strings as the real one is.
        let d = FakeDictionary([
            "en": ["wt", "ye", "the", "in", "app"],
            "uk": ["це", "ну", "еру", "місто"],
            "ru": ["це", "ну", "город"],
        ])
        d.alphabets = ["en": "abcdefghijklmnopqrstuvwxyz",
                       "uk": "абвгдеєжзиіїйклмнопрстуфхцчшщьюя",
                       "ru": "абвгдежзийклмнопрстуфхцчшщъыьэюя"]
        return d
    }()
    private lazy var resolver = NWayResolver(catalog: catalog, dict: dict, exceptions: FakeExceptions())

    func testTheReportedDefect() {
        // `це`'s keystrokes with the English layout active. Before the list this was
        // `keep(.validInCurrent)` — "already a word in this layout's language" — and the user's
        // Ukrainian stayed on screen as `wt`. Now `wt` cannot vouch for itself, so the Ukrainian and
        // Ukrainian reading is the candidate, and at two letters the word is held for the phrase.
        //
        // Note which candidate survived: the Russian dictionary also accepts `це` (field log
        // `ru:'це' VALID`), which used to make the word ambiguous and hand it to the preference
        // setting. `це` is not a Russian word — Russian writes `это` — so the list drops that
        // reading too, and the word is now unambiguously Ukrainian.
        let outcome = resolver.evaluate(keys: Fixture.keys("wt"), capsLock: false)
        if case .keep(let reason) = outcome {
            XCTFail("'wt' still vouches for itself: \(reason)")
        }
        guard case .held(let original, let winners) = outcome else {
            return XCTFail("expected the word to be held for the phrase, got \(outcome)")
        }
        XCTAssertEqual(original, "wt")
        XCTAssertEqual(winners.map(\.lang), ["uk"])
    }

    func testTheReportedDefectIsFixedOutrightOnceThePhraseIsUkrainian() {
        // The same word inside a Ukrainian phrase — the ordinary case, since a sentence has longer
        // words in it — converts, which is what the user wanted all along.
        guard case .convert(let d) = resolver.evaluate(keys: Fixture.keys("wt"), capsLock: false,
                                                       phraseLang: "uk") else {
            return XCTFail("'wt' was not fixed even with the phrase reading as Ukrainian")
        }
        XCTAssertEqual(d.converted, "це")
        XCTAssertEqual(d.lang, "uk")
    }

    func testACorrectlyTypedShortWordIsStillKept() {
        // The dangerous direction: this must not convert English `in` into Russian `шт`.
        catalog.current = Fixture.en
        guard case .keep(let reason) = resolver.evaluate(keys: Fixture.keys("in"), capsLock: false,
                                                         phraseLang: "en") else {
            return XCTFail("a correctly typed English word was not kept")
        }
        XCTAssertEqual(reason, .validInCurrent)
    }

    func testTheMirrorDirection() {
        // English typed on the Ukrainian layout: `the` lands as `еру`, which the Ukrainian
        // dictionary accepts. Without the list this kept; now the English reading wins.
        catalog.current = Fixture.uk
        guard case .convert(let d) = resolver.evaluate(keys: Fixture.keysForCyrillic("еру", lang: "uk"),
                                                       capsLock: false, phraseLang: "en") else {
            return XCTFail("'еру' still vouches for itself")
        }
        XCTAssertEqual(d.converted, "the")
    }
}

import XCTest
@testable import Switcher3wCore

/// The precision property the app lives or dies by: **a typo must not be mistaken for the wrong
/// keyboard**.
///
/// A Ukrainian user abandoned the Windows build over this — "every typo or mistake makes switch to
/// EN from UK… quite big text with some crap in english layout here and there" — and the macOS
/// resolver reasoned exactly the same way. Measured there against natural prose, 2.9% of ordinary
/// single-edit typos were converted, and the layout went with each one, so the rest of the sentence
/// landed in the wrong alphabet until the user noticed. The fix is ported here in the same shape.
///
/// Two causes, both structural rather than accidental:
///
///   * A dictionary hit on a short word means almost nothing. 160 of the 676 two-letter Latin
///     strings are in the English dictionary — `ft`, `bf`, `kw`, `lb` — nearly all abbreviations
///     nobody types as a word.
///   * A Ukrainian typo is very often a real Russian word (`адже`→`даже`, `програма`→`программа`),
///     and those are long, so no length rule can help.
///
/// The statistical measurements live in the Windows port, which shares this algorithm and its two
/// thresholds; what is asserted here is that the same decisions come out.
@MainActor
final class TypoGuardTests: XCTestCase {

    private lazy var catalog = Fixture.catalog(current: Fixture.uk)
    private lazy var dict: FakeDictionary = {
        let d = FakeDictionary([
            // "friend"/"акшути" are not real words; the fixture is a set, and what these two test
            // is the length band, which only needs a valid en render and a one-edit uk neighbour.
            "en": ["here", "ft", "of", "we", "hello", "friend", "you're"],
            "uk": ["друкую", "текст", "адже", "привіт", "як", "ти", "пишеш", "акшути", "хороше"],
            "ru": ["даже", "программа", "хорошо"],
        ])
        // The near-miss check needs the language's letters to build a word's neighbours. Production
        // takes these from the keyboard layout; here they are stated outright.
        d.alphabets = [
            "en": "abcdefghijklmnopqrstuvwxyz",
            "uk": "абвгдеєжзиіїйклмнопрстуфхцчшщьюя",
            "ru": "абвгдежзийклмнопрстуфхцчшщъыьэюя",
        ]
        return d
    }()
    private lazy var resolver = NWayResolver(catalog: catalog, dict: dict,
                                             exceptions: FakeExceptions())

    /// Keystrokes that produce `word` on the Ukrainian layout.
    private func typing(_ word: String) -> [TypedKey] { Fixture.keysForCyrillic(word, lang: "uk") }

    // MARK: - the reported failure

    func testAFumbledWordIsNotReadAsTheWrongLayout() {
        // "акшутв" is "акшути" with one letter wrong. On a US layout those keystrokes read
        // "friend" — an English word, so a conversion really is on the table. Six letters, so the
        // near-miss check is trusted: it finds the neighbour and declines, which is the whole point.
        guard case .keep(let reason) = resolver.evaluate(keys: typing("акшутв"), capsLock: false) else {
            return XCTFail("a typo of a Ukrainian word was converted")
        }
        XCTAssertEqual(reason, .looksLikeATypo)
    }

    // MARK: - the guard is consulted only where it was measured to discriminate

    func testAFiveLetterWordIsNotSecondGuessedByTheNearMissCheck() {
        // "рукую" is one letter from "друкую" AND reads "here." on the US layout. At five letters
        // nearly every string has a real neighbour (30–40% false alarms measured at four), so the
        // guard is not consulted and the dictionary hit stands. This used to keep, two letters below
        // the documented band — Дякую, Слава, давай, Лови, chat, fine in a twelve-day log, no typos.
        guard case .convert(let d) = resolver.evaluate(keys: typing("рукую"), capsLock: false) else {
            return XCTFail("a five-letter wrong-layout word was refused by the near-miss check")
        }
        XCTAssertEqual(d.lang, "en")
    }

    func testTheSameTextInASiblingLanguageSwitchesOnlyTheLayoutWhenThePhraseAgrees() {
        // "хорошо" typed on the Ukrainian layout: not Ukrainian, Russian, and spelled identically
        // there. Ukrainian holds "хороше" one edit away, so the near-miss check would call it a
        // typo — but the phrase has already locked to Russian (a ы/э word converted earlier), which
        // is the corroboration a Ukrainian typist never produces. Layout switch, nothing to retype.
        guard case .convert(let d) = resolver.evaluate(keys: typing("хорошо"), capsLock: false,
                                                       phraseLang: "ru") else {
            return XCTFail("a same-text Russian word on the Ukrainian layout was kept despite a ru phrase")
        }
        XCTAssertEqual(d.lang, "ru")
        XCTAssertTrue(d.isLayoutOnly)
        XCTAssertEqual(d.original, d.converted)
    }

    func testTheSameTextWithoutAPhraseKeepsTheLayoutAndSaysWhy() {
        // The same word with nothing settled: a Ukrainian typo is as often a real Russian word
        // (адже→даже, добре→добр: 15 of 1,399 corpus typos, most too short for any guard), and
        // flipping the layout on it is the failure a Ukrainian writer left over. Kept, with a reason
        // of its own — the log must say the layout was deliberately left, not that a typo was seen.
        for word in ["хорошо", "даже"] {   // six letters and four: the rule does not depend on length
            dict.words["ru"]?.insert("даже")
            guard case .keep(let reason) = resolver.evaluate(keys: typing(word), capsLock: false) else {
                return XCTFail("\(word): a same-text word with no phrase was converted")
            }
            XCTAssertEqual(reason, .sameTextUncorroborated, word)
        }
    }

    func testTheShortWordBandIsJudgedOnTheWinnersCoreToo() {
        // "рухх" (рух with a doubled letter) renders "he[[" — a core of two letters, "he", which the
        // English dictionary accepts. Four typed letters do not make that hit worth more; the shorter
        // core decides, and two letters is held for the phrase, not converted.
        dict.words["en"]?.insert("he"); dict.words["uk"]?.insert("рух")
        guard case .held = resolver.evaluate(keys: typing("рухх"), capsLock: false) else {
            return XCTFail("a two-letter dictionary hit decided a word on its own")
        }
    }

    func testAContractionPassesTheGates() {
        // "you're" typed on the Ukrainian layout is "нщгєку" — the apostrophe key is є there.
        guard case .convert(let d) = resolver.evaluate(keys: typing("нщгєку"), capsLock: false) else {
            return XCTFail("a contraction was vetoed as code")
        }
        XCTAssertEqual(d.converted, "you're")
    }

    func testATokenWithoutLettersIsNotAWordAnywhere() {
        // The real validators accept an empty string, and the fake mirrors that. "1" and "11"
        // used to come back "valid in the current language" — and lock the phrase to it.
        for token in ["1", "11"] {
            guard case .keep(let reason) = resolver.evaluate(keys: Fixture.keys(token), capsLock: false) else {
                return XCTFail("\(token) was not kept")
            }
            XCTAssertEqual(reason, .notAWordAnywhere, token)
        }
    }

    func testAUkrainianTypoIsNotDraggedIntoRussian() {
        // "даже" is a real Russian word and a transposition of the Ukrainian "адже". For a Ukrainian
        // writer this is the worse failure of the two, and length cannot catch it.
        guard case .keep(let reason) = resolver.evaluate(keys: typing("даже"), capsLock: false,
                                                         phraseLang: "uk") else {
            return XCTFail("a Ukrainian typo was converted into Russian")
        }
        XCTAssertEqual(reason, .phraseDisagrees)
    }

    func testAWordAlreadyValidHereReportsThatItSettlesThePhrase() {
        guard case .keep(let reason) = resolver.evaluate(keys: typing("текст"), capsLock: false) else {
            return XCTFail("a correctly typed word was not kept")
        }
        // The caller pins the phrase on this, so it has to be distinguishable from "not a word".
        XCTAssertEqual(reason, .validInCurrent)
    }

    func testTheNearMissCheckIsOnlyPaidWhenAConversionIsOnTheTable() {
        // "текстт" is a fumble that is not a word in any other language either, so nothing was ever
        // proposed and the near-miss check is never consulted. The reason says which rule ran.
        guard case .keep(let reason) = resolver.evaluate(keys: typing("текстт"), capsLock: false) else {
            return XCTFail("expected the word to be kept")
        }
        XCTAssertEqual(reason, .notAWordAnywhere)
    }

    // MARK: - short words are decided by the phrase, not by the dictionary

    func testAShortWordWithNothingToGoOnIsHeldRatherThanGuessed() {
        catalog.current = Fixture.en
        guard case .held(let original, let winners) = resolver.evaluate(keys: typing("як"),
                                                                        capsLock: false) else {
            return XCTFail("a two-letter word was decided on its own")
        }
        XCTAssertEqual(original, "zr")                 // untouched on screen
        XCTAssertEqual(winners.map(\.lang), ["uk"])    // but the reading is remembered
    }

    func testAShortWordConvertsOnceThePhraseAgrees() {
        catalog.current = Fixture.en
        guard case .convert(let d) = resolver.evaluate(keys: typing("як"), capsLock: false,
                                                       phraseLang: "uk") else {
            return XCTFail("a short word was not converted even with the phrase agreeing")
        }
        XCTAssertEqual(d.converted, "як")
    }

    // MARK: - recall, which is what the caution must not cost

    func testALongWordInTheWrongLayoutStillConverts() {
        catalog.current = Fixture.en
        guard case .convert(let d) = resolver.evaluate(keys: typing("привіт"), capsLock: false) else {
            return XCTFail("wrong-layout typing was not corrected — the app has stopped working")
        }
        XCTAssertEqual(d.converted, "привіт")
        XCTAssertEqual(d.lang, "uk")
    }

    /// The bet the short-word rule makes: a held word is not a lost word. The phrase tracker
    /// re-renders it as soon as something settles the language, which is why deferring costs nothing
    /// across a sentence even though it looks ruinous word by word.
    func testHeldWordsAreRepairedByTheWordThatSettlesThePhrase() {
        catalog.current = Fixture.en
        let tracker = PhraseTracker { [catalog] keys, layoutID in
            catalog.render(keys, layoutID: layoutID)
        }
        for word in ["як", "ти"] {
            let keys = typing(word)
            guard case .held(let shown, _) = resolver.evaluate(keys: keys, capsLock: false) else {
                return XCTFail("expected \(word) to be held")
            }
            tracker.record(keys: keys, shownText: shown, spacesAfter: 1, kind: .defaulted(lang: "en"))
        }
        let correction = tracker.correction(toLang: "uk", layoutID: Fixture.uk)
        XCTAssertEqual(correction?.newSegment, "як ти ")
    }

    // MARK: - the guards restrain the app, not the user

    func testTheManualTriggerIsNotSecondGuessed() {
        catalog.current = Fixture.en
        // Two letters, which auto-fix declines to judge. An explicit request is entitled to an
        // answer anyway, and to the right one first.
        let plan = resolver.manualPlan(keys: typing("як"), capsLock: false, ambiguousLang: "uk")
        XCTAssertEqual(plan?.candidates.first?.targetLayoutID, Fixture.uk)
    }

    func testTheNearMissCheckDoesNotVetoAnExplicitRequest() {
        // "рукую" is declined by auto-fix above; asked directly, it must still offer English.
        let plan = resolver.manualPlan(keys: typing("рукую"), capsLock: false, ambiguousLang: "uk")
        XCTAssertEqual(plan?.candidates.first?.targetLayoutID, Fixture.en)
    }

    // MARK: - the guard degrades safely

    func testWithoutAnAlphabetTheNearMissCheckSimplyDoesNotRun() {
        // A validator that cannot name a language's letters must fall back to the old behaviour
        // rather than veto everything — otherwise an incomplete adapter would silently switch
        // auto-fix off and look like the app doing nothing.
        dict.alphabets = [:]
        XCTAssertFalse(TypoGuard.nearMiss("рукую", lang: "uk", dict: dict))
    }
}

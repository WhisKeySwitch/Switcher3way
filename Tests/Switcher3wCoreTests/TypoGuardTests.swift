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
            "en": ["here", "ft", "of", "we", "hello"],
            "uk": ["друкую", "текст", "адже", "привіт", "як", "ти", "пишеш"],
            "ru": ["даже", "программа"],
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
        // "рукую" is "друкую" with the д dropped. On a US layout those keystrokes read "here." —
        // genuinely an English word, so a conversion really is on the table. The near-miss check
        // finds "друкую" one keystroke away and declines, which is the whole point.
        guard case .keep(let reason) = resolver.evaluate(keys: typing("рукую"), capsLock: false) else {
            return XCTFail("a typo of a Ukrainian word was converted")
        }
        XCTAssertEqual(reason, .looksLikeATypo)
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

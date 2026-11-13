import XCTest
@testable import Switcher3wCore

/// Phrase-level memory: the thing that lets a later ru-only word retro-correct earlier words that
/// were defaulted to uk. Precision-first — it refuses whenever it cannot account for the screen
/// exactly, and every one of those refusals is a case below.
@MainActor
final class PhraseTrackerTests: XCTestCase {

    /// A renderer that "converts" by upper-casing and tagging the layout, so a correction's text is
    /// checkable without dragging real layouts in.
    private func tracker(render: @escaping (_ keys: [TypedKey], _ layoutID: String) -> String?)
        -> PhraseTracker {
        PhraseTracker(render: render)
    }

    private func simpleTracker() -> PhraseTracker {
        tracker { keys, layoutID in "\(layoutID):\(keys.count)" }
    }

    private func keys(_ n: Int) -> [TypedKey] {
        (0..<n).map { TypedKey(keyCode: UInt16($0), shift: false, caps: false) }
    }

    func testLockedLangIsNilUntilAWordLocksIt() {
        let t = simpleTracker()
        XCTAssertNil(t.lockedLang)
        t.record(keys: keys(3), shownText: "abc", spacesAfter: 1, kind: .defaulted(lang: "uk"))
        XCTAssertNil(t.lockedLang, "a defaulted word must not lock the phrase")
        t.record(keys: keys(3), shownText: "def", spacesAfter: 1, kind: .locked(lang: "ru"))
        XCTAssertEqual(t.lockedLang, "ru")
    }

    func testCorrectionRewritesDefaultedWordsOfAnotherLanguage() {
        let t = tracker { _, layoutID in layoutID == "ru" ? "ХОРОШО" : nil }
        t.record(keys: keys(6), shownText: "добре", spacesAfter: 1, kind: .defaulted(lang: "uk"))
        guard let c = t.correction(toLang: "ru", layoutID: "ru") else {
            return XCTFail("a uk-defaulted word must be correctable toward ru")
        }
        XCTAssertEqual(c.oldSegment, "добре ")
        XCTAssertEqual(c.newSegment, "ХОРОШО ")
        XCTAssertEqual(c.firstIndex, 0)
    }

    func testNeutralWordsAreReproducedVerbatim() {
        // A word that was correct as typed keeps its text; only the defaulted ones re-render.
        let t = tracker { _, _ in "RU" }
        t.record(keys: keys(3), shownText: "the", spacesAfter: 1, kind: .neutral)
        t.record(keys: keys(5), shownText: "добре", spacesAfter: 1, kind: .defaulted(lang: "uk"))
        guard let c = t.correction(toLang: "ru", layoutID: "ru") else {
            return XCTFail("expected a correction")
        }
        XCTAssertEqual(c.firstIndex, 1, "the segment starts at the first defaulted word")
        XCTAssertEqual(c.oldSegment, "добре ")
        XCTAssertEqual(c.newSegment, "RU ")
    }

    /// A word that is no word where it was typed, between a held word and the word that converts,
    /// converts with them. Before, it was reproduced verbatim and left stranded in Latin.
    func testUnrecognisedWordsInsideTheSegmentConvert() {
        let t = tracker { keys, _ in "UK\(keys.count)" }
        t.record(keys: keys(2), shownText: "Wt", spacesAfter: 1, kind: .defaulted(lang: "en"))
        t.record(keys: keys(3), shownText: "xbv", spacesAfter: 1, kind: .unrecognised(lang: "en"))
        t.record(keys: keys(1), shownText: "z", spacesAfter: 1, kind: .unrecognised(lang: "en"))
        guard let c = t.correction(toLang: "uk", layoutID: "uk") else {
            return XCTFail("expected a correction")
        }
        XCTAssertEqual(c.oldSegment, "Wt xbv z ")
        XCTAssertEqual(c.newSegment, "UK2 UK3 UK1 ")
    }

    /// …but never starts one: a lone English typo before a Ukrainian word stays as typed.
    func testAnUnrecognisedWordDoesNotStartACorrection() {
        let t = simpleTracker()
        t.record(keys: keys(8), shownText: "Exchanfe", spacesAfter: 1, kind: .unrecognised(lang: "en"))
        XCTAssertNil(t.correction(toLang: "uk", layoutID: "uk"))

        // Before the first defaulted word, it is outside the segment and untouched.
        t.record(keys: keys(2), shownText: "Wt", spacesAfter: 1, kind: .defaulted(lang: "en"))
        let c = t.correction(toLang: "uk", layoutID: "uk")
        XCTAssertEqual(c?.firstIndex, 1)
        XCTAssertEqual(c?.oldSegment, "Wt ")
    }

    /// An unrecognised word already in the target language is not re-rendered.
    func testUnrecognisedWordInTheTargetLanguageStays() {
        let t = tracker { _, _ in "RE" }
        t.record(keys: keys(2), shownText: "Wt", spacesAfter: 1, kind: .defaulted(lang: "en"))
        t.record(keys: keys(3), shownText: "абв", spacesAfter: 1, kind: .unrecognised(lang: "uk"))
        XCTAssertEqual(t.correction(toLang: "uk", layoutID: "uk")?.newSegment, "RE абв ")
    }

    func testNoCorrectionWhenNothingWasDefaultedElsewhere() {
        let t = simpleTracker()
        t.record(keys: keys(3), shownText: "abc", spacesAfter: 1, kind: .neutral)
        t.record(keys: keys(3), shownText: "def", spacesAfter: 1, kind: .defaulted(lang: "ru"))
        XCTAssertNil(t.correction(toLang: "ru", layoutID: "ru"),
                     "words already in the target language need no correction")
    }

    func testContradictoryPhraseRefusesToCorrect() {
        // A phrase locked to uk plus a new ru word is contradictory — precision-first, touch nothing.
        let t = simpleTracker()
        t.record(keys: keys(3), shownText: "хай", spacesAfter: 1, kind: .locked(lang: "uk"))
        t.record(keys: keys(5), shownText: "добре", spacesAfter: 1, kind: .defaulted(lang: "uk"))
        XCTAssertNil(t.correction(toLang: "ru", layoutID: "ru"))
    }

    func testCorrectionRefusedWhenReRenderFails() {
        let t = tracker { _, _ in nil }   // renderer cannot produce the target text
        t.record(keys: keys(5), shownText: "добре", spacesAfter: 1, kind: .defaulted(lang: "uk"))
        XCTAssertNil(t.correction(toLang: "ru", layoutID: "ru"))
    }

    func testCorrectionRefusedBeyondTheLengthCap() {
        let t = tracker { _, _ in "x" }
        let long = String(repeating: "a", count: PhraseTracker.maxCorrectionLength + 1)
        t.record(keys: keys(3), shownText: long, spacesAfter: 0, kind: .defaulted(lang: "uk"))
        XCTAssertNil(t.correction(toLang: "ru", layoutID: "ru"),
                     "an over-long erase chain must be refused, not attempted")
    }

    func testResetClearsWordsAndBumpsGeneration() {
        let t = simpleTracker()
        t.record(keys: keys(3), shownText: "abc", spacesAfter: 1, kind: .neutral)
        let gen = t.generation
        t.reset()
        XCTAssertTrue(t.words.isEmpty)
        XCTAssertNotEqual(t.generation, gen, "a reset must invalidate in-flight completions")
    }

    func testRecordFromAStaleGenerationIsDropped() {
        // A retype completion that lost the race against a click/Enter must not corrupt the phrase.
        let t = simpleTracker()
        let stale = t.generation
        t.reset()
        t.record(keys: keys(3), shownText: "abc", spacesAfter: 1, kind: .neutral, ifGeneration: stale)
        XCTAssertTrue(t.words.isEmpty)
    }

    func testExtraSpaceWidensTheGapAfterTheLastWord() {
        let t = tracker { _, _ in "RU" }
        t.record(keys: keys(5), shownText: "добре", spacesAfter: 1, kind: .defaulted(lang: "uk"))
        t.noteExtraSpace()
        guard let c = t.correction(toLang: "ru", layoutID: "ru") else {
            return XCTFail("expected a correction")
        }
        XCTAssertEqual(c.oldSegment, "добре  ", "the multi-space run must stay exact")
    }

    func testExtraSpaceWithNoWordsIsHarmless() {
        let t = simpleTracker()
        t.noteExtraSpace()
        XCTAssertTrue(t.words.isEmpty)
    }

    func testConfirmCommitsTheCorrectedWords() {
        let t = tracker { _, _ in "RU" }
        t.record(keys: keys(5), shownText: "добре", spacesAfter: 1, kind: .defaulted(lang: "uk"))
        guard let c = t.correction(toLang: "ru", layoutID: "ru") else {
            return XCTFail("expected a correction")
        }
        t.confirm(c, ifGeneration: t.generation)
        XCTAssertEqual(t.words.first?.shownText, "RU")
        XCTAssertEqual(t.words.first?.kind, .defaulted(lang: "ru"))
    }

    func testConfirmFromAStaleGenerationIsDropped() {
        let t = tracker { _, _ in "RU" }
        t.record(keys: keys(5), shownText: "добре", spacesAfter: 1, kind: .defaulted(lang: "uk"))
        guard let c = t.correction(toLang: "ru", layoutID: "ru") else {
            return XCTFail("expected a correction")
        }
        let stale = t.generation
        t.reset()
        t.confirm(c, ifGeneration: stale)
        XCTAssertTrue(t.words.isEmpty, "a correction that lost the race must not resurrect words")
    }

    func testConfirmResetsWhenThePhraseChangedShape() {
        // A word arrived while the retype ran: the memory no longer matches the screen, so the
        // tracker drops everything rather than committing over the wrong span.
        let t = tracker { _, _ in "RU" }
        t.record(keys: keys(5), shownText: "добре", spacesAfter: 1, kind: .defaulted(lang: "uk"))
        guard let c = t.correction(toLang: "ru", layoutID: "ru") else {
            return XCTFail("expected a correction")
        }
        t.record(keys: keys(3), shownText: "new", spacesAfter: 1, kind: .neutral)
        t.confirm(c, ifGeneration: t.generation)
        XCTAssertTrue(t.words.isEmpty)
    }
}

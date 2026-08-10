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

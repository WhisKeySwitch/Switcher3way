import XCTest
@testable import Switcher3wCore

/// The cheap vetoes that run before any dictionary lookup. These are the app's precision knobs:
/// every one of them exists because letting that input through produced a wrong conversion.
final class SoftGatesTests: XCTestCase {

    func testRejectsSingleLetter() {
        // "я" / "a" / "i" are valid words in some language and hopelessly ambiguous between layouts.
        XCTAssertFalse(SoftGates.passes("a", capsLock: false))
        XCTAssertFalse(SoftGates.passes("я", capsLock: false))
        XCTAssertFalse(SoftGates.passes("", capsLock: false))
    }

    func testAcceptsTwoLetterWords() {
        XCTAssertTrue(SoftGates.passes("на", capsLock: false))
        XCTAssertTrue(SoftGates.passes("go", capsLock: false))
    }

    func testRejectsNonLetters() {
        // digits / punctuation / URLs / code / email — the whole token must be letters.
        XCTAssertFalse(SoftGates.passes("abc1", capsLock: false))
        XCTAssertFalse(SoftGates.passes("a.b", capsLock: false))
        XCTAssertFalse(SoftGates.passes("test@mail", capsLock: false))
        XCTAssertFalse(SoftGates.passes("привіт!", capsLock: false))
    }

    func testAdmitsAnInternalApostropheOrHyphen() {
        // Contractions and hyphenated words are ordinary words of these languages, and they pass
        // when typed in their own layout — vetoing them as code cost `You're`, `That's` and `Кто-то`
        // their conversion in a field log.
        XCTAssertTrue(SoftGates.passes("you're", capsLock: false))
        XCTAssertTrue(SoftGates.passes("You\u{2019}re", capsLock: false))
        XCTAssertTrue(SoftGates.passes("кто-то", capsLock: false))
        XCTAssertTrue(SoftGates.passes("будь-ласка", capsLock: false))
    }

    func testOtherInternalPunctuationIsStillCode() {
        XCTAssertFalse(SoftGates.passes("a_b", capsLock: false))
        XCTAssertFalse(SoftGates.passes("a/b", capsLock: false))
        XCTAssertFalse(SoftGates.passes("v2x", capsLock: false))
        // Edge joiners are not words either (letterCore trims them before the gate normally runs).
        XCTAssertFalse(SoftGates.passes("-abc", capsLock: false))
        XCTAssertFalse(SoftGates.passes("abc'", capsLock: false))
    }

    func testRejectsAcronymsWhenCapsLockIsOff() {
        XCTAssertFalse(SoftGates.passes("USA", capsLock: false))
        XCTAssertFalse(SoftGates.passes("НДС", capsLock: false))
    }

    func testAcceptsAllCapsUnderCapsLock() {
        // Under Caps Lock everything is uppercase — that is not an acronym, so the veto lifts.
        XCTAssertTrue(SoftGates.passes("USA", capsLock: true))
        XCTAssertTrue(SoftGates.passes("ПРИВІТ", capsLock: true))
    }

    func testRejectsCamelCaseWhenCapsLockIsOff() {
        XCTAssertFalse(SoftGates.passes("camelCase", capsLock: false))
        XCTAssertFalse(SoftGates.passes("PascalCase", capsLock: false))
    }

    func testAcceptsCamelCaseShapeUnderCapsLock() {
        XCTAssertTrue(SoftGates.passes("camelCase", capsLock: true))
    }

    func testRejectsMixedScriptInEitherShiftState() {
        // Latin + Cyrillic in one token is almost always code, never a word — and that is true
        // whatever the shift state was. The veto used to share a function with the camelCase one
        // and was skipped along with it under Caps Lock.
        XCTAssertFalse(SoftGates.passes("приvit", capsLock: false))
        XCTAssertFalse(SoftGates.passes("приvit", capsLock: true))
        XCTAssertFalse(SoftGates.passes("ПРИVIT", capsLock: true))
    }

    func testLeadingCapitalIsFine() {
        XCTAssertTrue(SoftGates.passes("Привіт", capsLock: false))
        XCTAssertTrue(SoftGates.passes("Hello", capsLock: false))
    }

    // MARK: - letter core

    func testLetterCoreTrimsEdgePunctuation() {
        XCTAssertEqual(SoftGates.letterCore("привіт!"), "привіт")
        XCTAssertEqual(SoftGates.letterCore("(привіт)"), "привіт")
        XCTAssertEqual(SoftGates.letterCore("«hello»,"), "hello")
        XCTAssertEqual(SoftGates.letterCore("...word..."), "word")
    }

    func testLetterCoreKeepsInteriorPunctuation() {
        // Only the EDGES are trimmed — an interior character is kept, and the gate then decides:
        // "a.b" is code and stays out, while "don't" is a word and passes (see the joiner tests).
        XCTAssertEqual(SoftGates.letterCore("don't"), "don't")
        XCTAssertEqual(SoftGates.letterCore("a.b"), "a.b")
        XCTAssertFalse(SoftGates.passes(SoftGates.letterCore("a.b"), capsLock: false))
    }

    func testLetterCoreOfNonLettersIsEmpty() {
        XCTAssertEqual(SoftGates.letterCore("..."), "")
        XCTAssertEqual(SoftGates.letterCore("123"), "")
        XCTAssertFalse(SoftGates.passes(SoftGates.letterCore("..."), capsLock: false))
    }

    func testTrimmedWordPassesTheGates() {
        // The point of the core: a trailing "!" must not hide an otherwise-valid word.
        XCTAssertFalse(SoftGates.passes("привіт!", capsLock: false))
        XCTAssertTrue(SoftGates.passes(SoftGates.letterCore("привіт!"), capsLock: false))
    }
}

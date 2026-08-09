import XCTest
@testable import Switcher3wCore

/// The N-way decision itself: keep / convert / ambiguous, plus the two explicit user overrides.
@MainActor
final class EvaluateTests: XCTestCase {

    // Lazily built rather than assembled in `setUp`: XCTest creates a fresh instance per test
    // method, so these are already per-test state, and `setUp` is nonisolated while all of this
    // is main-actor bound.
    private lazy var catalog = Fixture.catalog(current: Fixture.en)
    private lazy var dict = FakeDictionary([
        "en": ["hello", "the", "cat"],
        "uk": ["привіт", "добре", "але", "місто", "город"],
        "ru": ["привет", "добре", "хорошо", "город"],
    ])
    private lazy var exceptions = FakeExceptions()
    private lazy var resolver = NWayResolver(catalog: catalog, dict: dict, exceptions: exceptions)

    /// A pristine catalog kept aside for `latinFor`, so a test that deliberately breaks rendering
    /// on `catalog` can still express which keystrokes it means.
    private lazy var reference = Fixture.catalog(current: Fixture.en)

    /// Typing "ghbdsn" on the US layout is "привіт"… only in the sense that the keystrokes were
    /// meant for a Cyrillic layout. Here we use the fixture's own correspondence.
    private func outcome(_ latin: String, caps: Bool = false) -> NWayResolver.Outcome {
        resolver.evaluate(keys: Fixture.keys(latin, caps: caps), capsLock: caps)
    }

    func testKeepsAWordValidInTheCurrentLanguage() {
        // "hello" is a real English word and English is active → nothing to fix.
        guard case .keep = outcome("hello") else {
            return XCTFail("a valid current-language word must be kept")
        }
    }

    func testConvertsAWordValidInExactlyOneOtherLanguage() {
        // The keystrokes for "місто" typed while US is active.
        let latin = latinFor("місто", lang: "uk")
        guard case .convert(let d) = outcome(latin) else {
            return XCTFail("expected a conversion, got \(outcome(latin))")
        }
        XCTAssertEqual(d.lang, "uk")
        XCTAssertEqual(d.converted, "місто")
        XCTAssertEqual(d.targetLayoutID, Fixture.uk)
    }

    func testReportsAmbiguityWhenTwoLanguagesValidate() {
        // "добре" is in both the uk and ru word sets — the resolver must not pick for itself.
        let latin = latinFor("добре", lang: "uk")
        guard case .ambiguous(_, let winners) = outcome(latin) else {
            return XCTFail("expected ambiguity, got \(outcome(latin))")
        }
        XCTAssertEqual(Set(winners.map(\.lang)), ["uk", "ru"])
    }

    func testKeepsWhenNoLanguageValidates() {
        guard case .keep = outcome("qwzx") else {
            return XCTFail("gibberish must be left alone")
        }
    }

    func testKeepsWhenTheWordFailsTheSoftGates() {
        // Single letter: valid in some language, but hopelessly ambiguous — never converted.
        guard case .keep = outcome(latinFor("я", lang: "uk")) else {
            return XCTFail("a single letter must never convert")
        }
    }

    func testAlwaysConvertOverridesTheDictionary() {
        // "але" is a uk word; make the current-language render valid too so the normal path would
        // keep it, then prove the explicit override still converts.
        let latin = latinFor("але", lang: "uk")
        dict.words["en"]?.insert(latin)
        guard case .keep = outcome(latin) else {
            return XCTFail("precondition: this must be kept without the override")
        }
        exceptions.always.insert("але")
        guard case .convert(let d) = outcome(latin) else {
            return XCTFail("always-convert must override a valid current-language word")
        }
        XCTAssertEqual(d.converted, "але")
    }

    func testAlwaysConvertMatchesTheConvertedForm() {
        // The list holds the INTENDED result, not the mistyped form — otherwise a correctly typed
        // word would be converted back and forth.
        let latin = latinFor("місто", lang: "uk")
        exceptions.always.insert(latin)          // the typed (wrong) form
        guard case .convert(let d) = outcome(latin) else {
            return XCTFail("this converts on its own merits anyway")
        }
        XCTAssertEqual(d.converted, "місто", "matching must be on the target form")
    }

    func testSkipsLanguagesWithoutADictionary() {
        // With no uk dictionary installed, a uk-only word has no candidate to win with.
        dict.unavailable.insert("uk")
        guard case .keep = outcome(latinFor("місто", lang: "uk")) else {
            return XCTFail("a language without a dictionary cannot win")
        }
    }

    func testKeepsWhenTheCurrentLayoutIsNotResolvable() {
        catalog.current = "com.apple.keylayout.Nonexistent"
        guard case .keep = outcome("hello") else {
            return XCTFail("an unresolvable current layout must be a no-op, not a guess")
        }
    }

    func testKeepsWhenTheCurrentLayoutCannotRender() {
        catalog.unrenderable.insert(Fixture.en)
        guard case .keep = outcome(latinFor("місто", lang: "uk")) else {
            return XCTFail("without a current-layout render there is no original text to replace")
        }
    }

    func testEmptyInputIsKept() {
        guard case .keep = resolver.evaluate(keys: [], capsLock: false) else {
            return XCTFail("empty input must be a no-op")
        }
    }

    func testCapsLockWordStillConverts() {
        // Under Caps Lock the render is uppercase; the dictionary check is case-insensitive.
        let latin = latinFor("місто", lang: "uk")
        guard case .convert(let d) = outcome(latin, caps: true) else {
            return XCTFail("Caps Lock must not defeat detection")
        }
        XCTAssertEqual(d.converted, "МІСТО")
    }

    func testPunctuationAttachedToAWordStillConverts() {
        // Validation runs on the letter CORE, so a trailing "!" must not hide an otherwise-valid
        // word — while the whole token is still re-rendered in the target layout.
        var keys = Fixture.keys(latinFor("місто", lang: "uk"))
        keys.append(TypedKey(keyCode: 18, shift: true, caps: false))   // "!" in every layout
        guard case .convert(let d) = resolver.evaluate(keys: keys, capsLock: false) else {
            return XCTFail("a trailing '!' must not hide a valid word")
        }
        XCTAssertEqual(d.converted, "місто!")
    }

    func testPunctuationKeysThatAreLettersOnCyrillicDoNotConvert() {
        // The "," key is "б" on the Cyrillic layouts, so those keystrokes render as "містоб" —
        // not a word, correctly left alone. This is the counterpart to the case above and the
        // reason letter-core trimming cannot simply strip every non-letter from the render.
        let latin = latinFor("місто", lang: "uk") + ","
        guard case .keep = outcome(latin) else {
            return XCTFail("'містоб' is not a word and must be kept")
        }
    }

    // MARK: - helper

    /// The Latin string whose keystrokes render as `word` in `lang` — i.e. what the user actually
    /// pressed while the wrong layout was active.
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

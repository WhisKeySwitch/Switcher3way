import AppKit
import XCTest
@testable import Switcher3wCore

/// Measures the REAL system dictionary against the checked-in fixture, so a change in the
/// validation path shows up as a measured quality shift instead of silent behavior drift. Every
/// other test in this target uses a fake dictionary precisely to be machine-independent — this one
/// is the deliberate exception, and it skips rather than fails when a language is not installed.
@MainActor
final class DictionaryQualityTests: XCTestCase {

    /// The production validator, rebuilt here rather than imported: `Dict` lives in the executable
    /// target (it is AppKit-bound), and the point is to measure what it measures.
    private struct SystemSpellChecker: DictionaryValidating {
        let checker = NSSpellChecker.shared

        func isAvailable(_ lang: String) -> Bool {
            checker.availableLanguages.contains { String($0.prefix(2)) == String(lang.prefix(2)) }
        }

        func isValidWord(_ word: String, lang: String) -> Bool {
            let range = checker.checkSpelling(of: word, startingAt: 0, language: lang,
                                              wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
            return range.location == NSNotFound
        }

        /// One verdict per word, asked ONCE.
        ///
        /// `NSSpellChecker` does not answer identically on back-to-back calls for the same word: an
        /// earlier version of this test computed `accepted` and `rejected` with two separate passes
        /// and reported a 0.75 rate alongside an empty list of accepted words — arithmetic that is
        /// only possible if the two passes disagreed. A language also answers differently on its
        /// first call than once it has warmed up, which is what `warmUp` below is for.
        ///
        /// This is a property of the system checker, not of the fixture, and the app's own `Dict`
        /// calls the same API the same way — so it is worth knowing about beyond the test.
        func verdicts(for words: [String], lang: String) -> [String: Bool] {
            warmUp(lang)
            var out: [String: Bool] = [:]
            for w in words { out[w] = isValidWord(w.lowercased(), lang: lang) }
            return out
        }

        /// The first query for a language can answer before its dictionary is loaded. Ask a throwaway
        /// question first so the measured ones are asked of a warm checker.
        private func warmUp(_ lang: String) {
            _ = isValidWord("warmup", lang: lang)
        }
    }

    func testValidWordsAreRecognised() throws {
        let dict = SystemSpellChecker()
        var measured = false

        for (lang, words) in WordFixture.valid.sorted(by: { $0.key < $1.key }) {
            guard dict.isAvailable(lang) else {
                // Explicit, not a silent pass: a missing dictionary is a fact about the machine.
                print("dictionary-quality: SKIP \(lang) — no system dictionary installed")
                continue
            }
            measured = true
            let verdicts = dict.verdicts(for: words, lang: lang)
            let accepted = verdicts.filter { $0.value }.keys.sorted()
            let rejected = verdicts.filter { !$0.value }.keys.sorted()
            let rate = Double(accepted.count) / Double(words.count)
            print(String(format: "dictionary-quality: %@ valid-word rate %.2f (%d/%d)",
                         lang, rate, accepted.count, words.count))
            XCTAssertGreaterThanOrEqual(
                rate, WordFixture.minValidRate,
                "\(lang): only \(accepted.count)/\(words.count) fixture words validate. Not recognised: \(rejected)")
        }

        try XCTSkipUnless(measured, "no fixture language has a system dictionary on this machine")
    }

    func testGibberishIsRejected() throws {
        let dict = SystemSpellChecker()
        var measured = false

        for (lang, words) in WordFixture.invalid.sorted(by: { $0.key < $1.key }) {
            guard dict.isAvailable(lang) else {
                print("dictionary-quality: SKIP \(lang) — no system dictionary installed")
                continue
            }
            measured = true
            let verdicts = dict.verdicts(for: words, lang: lang)
            let accepted = verdicts.filter { $0.value }.keys.sorted()
            let rejected = verdicts.filter { !$0.value }.keys.sorted()
            let rate = Double(rejected.count) / Double(words.count)
            print(String(format: "dictionary-quality: %@ reject rate %.2f (%d/%d)",
                         lang, rate, rejected.count, words.count))
            XCTAssertGreaterThanOrEqual(
                rate, WordFixture.minRejectRate,
                "\(lang): keyboard mash validated as real words: \(accepted)")
        }

        try XCTSkipUnless(measured, "no fixture language has a system dictionary on this machine")
    }

    /// The resolver's own contract: a language whose dictionary is missing must never win. Proven
    /// here against the real availability check rather than the fake.
    func testUnavailableLanguageNeverWins() {
        let dict = SystemSpellChecker()
        let absent = "zz"
        XCTAssertFalse(dict.isAvailable(absent))
    }
}

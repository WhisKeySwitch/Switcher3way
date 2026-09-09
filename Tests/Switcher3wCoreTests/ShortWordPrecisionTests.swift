import XCTest
@testable import Switcher3wCore

/// Measures `ShortWords` against the short words of natural prose. The list decides whether a
/// dictionary hit on a short word is believed, so an omission is not a missed conversion — it is a
/// *false* one waiting for a phrase to agree with it. This is the gate that keeps the lists honest,
/// and it is a measurement, not an assertion: it reports coverage and fails below 100%.
@MainActor
final class ShortWordPrecisionTests: XCTestCase {

    func testEveryShortWordOfOrdinaryProseIsAdmitted() {
        var worst = 1.0
        for (lang, words) in ShortWordFixture.inProse.sorted(by: { $0.key < $1.key }) {
            XCTAssertTrue(ShortWords.covers(lang), "\(lang) has no list at all")
            let missing = words.filter { !ShortWords.admits($0, lang: lang) }
            let rate = Double(words.count - missing.count) / Double(words.count)
            worst = min(worst, rate)
            print(String(format: "short-word coverage %@: %.0f%% (%d/%d)", lang,
                         rate * 100, words.count - missing.count, words.count))
            XCTAssertTrue(missing.isEmpty,
                          "\(lang): these turn up in ordinary writing and would be converted away: \(missing)")
        }
        XCTAssertEqual(worst, 1.0, accuracy: 0.0001)
    }

    /// The other half of the bargain: the list must not be so generous that it re-admits the noise
    /// the change exists to exclude. Each of these is accepted by a real dictionary and is not a
    /// word anyone types, and each one blocked a real conversion in the field log.
    func testTheNoiseStaysOut() {
        let noise: [String: [String]] = [
            "en": ["wt", "ye", "pf", "lys", "oe", "ee", "ae", "ort", "fro"],
            "uk": ["еру", "шт", "ща", "цу", "гл", "фт", "ыв"],
            "ru": ["еру", "ща", "цу", "гл", "ыв", "це"],
        ]
        for (lang, words) in noise.sorted(by: { $0.key < $1.key }) {
            let admitted = words.filter { ShortWords.admits($0, lang: lang) }
            XCTAssertTrue(admitted.isEmpty, "\(lang) re-admitted dictionary noise: \(admitted)")
        }
    }

    // MARK: - the reported defect, against the dictionary the user actually has

    #if canImport(AppKit)
    /// The whole point, measured against the real system dictionary rather than a fake: the words a
    /// user typed in the wrong layout and got back untouched, because the English dictionary vouched
    /// for the Latin noise they had landed as.
    func testTheFieldLogsMissedWordsAreNowRecoverable() throws {
        let dict = RealDictionary()
        try XCTSkipUnless(dict.isAvailable("uk") && dict.isAvailable("en"),
                          "needs both the English and Ukrainian system dictionaries")
        let catalog = Fixture.catalog(current: Fixture.en)
        let resolver = NWayResolver(catalog: catalog, dict: dict, exceptions: FakeExceptions())

        // Typed with the English layout active, meaning the Ukrainian word. Each of these was kept
        // as "already a word in this layout's language" in the 2026-08-27..09-09 log.
        for (typed, meant) in [("wt", "це"), ("ye", "ну")] {
            let keys = Fixture.keys(typed)
            if case .keep(let reason) = resolver.evaluate(keys: keys, capsLock: false) {
                XCTFail("'\(typed)' still vouches for itself (\(reason)) — \(meant) stays broken")
            }
            // Inside a Ukrainian phrase, which is the ordinary case, it is fixed outright.
            guard case .convert(let d) = resolver.evaluate(keys: keys, capsLock: false,
                                                           phraseLang: "uk") else {
                return XCTFail("'\(typed)' was not converted even with a Ukrainian phrase")
            }
            XCTAssertEqual(d.converted, meant)
        }
    }

    /// And the words the user genuinely typed in English must still be left alone, with the real
    /// dictionary and a Ukrainian phrase around them — the direction that would cost trust.
    func testRealEnglishInsideAUkrainianPhraseIsStillKept() throws {
        let dict = RealDictionary()
        try XCTSkipUnless(dict.isAvailable("uk") && dict.isAvailable("en"),
                          "needs both the English and Ukrainian system dictionaries")
        let catalog = Fixture.catalog(current: Fixture.en)
        let resolver = NWayResolver(catalog: catalog, dict: dict, exceptions: FakeExceptions())
        var converted: [String] = []
        for word in ShortWordFixture.inProse["en"] ?? [] {
            let keys = Fixture.keys(word)
            if case .convert(let d) = resolver.evaluate(keys: keys, capsLock: false, phraseLang: "uk") {
                converted.append("\(word)→\(d.converted)")
            }
        }
        XCTAssertTrue(converted.isEmpty, "real English words converted away: \(converted)")
    }
    #endif
}

#if canImport(AppKit)
import AppKit

/// The production validator, rebuilt for the tests: `Dict` lives in the executable target, and the
/// point of these two cases is to measure what the user's machine actually answers.
@MainActor
struct RealDictionary: DictionaryValidating {
    let checker = NSSpellChecker.shared
    func isAvailable(_ lang: String) -> Bool {
        checker.availableLanguages.contains { String($0.prefix(2)) == String(lang.prefix(2)) }
    }
    func isValidWord(_ word: String, lang: String) -> Bool {
        checker.checkSpelling(of: word, startingAt: 0, language: lang, wrap: false,
                              inSpellDocumentWithTag: 0, wordCount: nil).location == NSNotFound
    }
    func alphabet(_ lang: String) -> String {
        switch String(lang.prefix(2)) {
        case "en": return "abcdefghijklmnopqrstuvwxyz"
        case "uk": return "абвгдеєжзиіїйклмнопрстуфхцчшщьюя"
        case "ru": return "абвгдежзийклмнопрстуфхцчшщъыьэюя"
        default:   return ""
        }
    }
    func vowels(_ lang: String) -> String {
        switch String(lang.prefix(2)) {
        case "en": return "aeiouy"
        case "uk": return "аеєиіїоуюя"
        case "ru": return "аеёиоуыэюя"
        default:   return ""
        }
    }
}
#endif

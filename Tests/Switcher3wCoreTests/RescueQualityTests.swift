// Measures the gibberish rescue against the REAL system dictionaries — the same deliberate
// exception to platform-independence as DictionaryQualityTests, and guarded the same way.
#if canImport(AppKit)
import AppKit
import XCTest
@testable import Switcher3wCore

/// Drives `RescueFixture` through the real resolver with `NSSpellChecker` behind it.
///
/// The two sides have different contracts, and the assertions encode that:
/// - keep side: ZERO conversions, hard assert per token. A false rescue costs the user their
///   sentence and their layout.
/// - rescue side: recall is REPORTED and gated loosely (`minRescueRecall`), because a missed
///   rescue costs one trigger tap. The printout is the measurement the design records.
@MainActor
final class RescueQualityTests: XCTestCase {

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

        // The production adapter's own values (CoreAdapters derives the alphabet from the layouts;
        // here the fixture's key table is the layout, so its letters are the honest equivalent).
        func alphabet(_ lang: String) -> String {
            switch lang {
            case "en": return "abcdefghijklmnopqrstuvwxyz"
            case "uk": return "абвгдежзийклмнопрстуфхцчшщьюяєіїґ"
            case "ru": return "абвгдежзийклмнопрстуфхцчшщъыьэюя"
            default: return ""
            }
        }

        func vowels(_ lang: String) -> String {
            switch lang {
            case "en": return "aeiouy"
            case "uk": return "аеєиіїоуюя"
            case "ru": return "аеёиоуыэюя"
            default: return ""
            }
        }
    }

    private func resolver(current: String) throws -> NWayResolver {
        let dict = SystemSpellChecker()
        try XCTSkipUnless(dict.isAvailable("en") && dict.isAvailable("uk") && dict.isAvailable("ru"),
                          "rescue-quality: needs en+uk+ru system dictionaries")
        // Warm the checker: a language can answer differently on its very first query.
        for lang in ["en", "uk", "ru"] { _ = dict.isValidWord("warmup", lang: lang) }
        return NWayResolver(catalog: Fixture.catalog(current: current),
                            dict: dict, exceptions: FakeExceptions())
    }

    private func isConverted(_ outcome: NWayResolver.Outcome) -> Bool {
        switch outcome {
        case .convert, .rescued, .ambiguous: return true
        case .keep, .held: return false
        }
    }

    // MARK: keep side — zero tolerance

    func testKeepSideEnglishIsNeverConverted() throws {
        let resolver = try resolver(current: Fixture.en)
        for token in RescueFixture.keepEnglish {
            let outcome = resolver.evaluate(keys: Fixture.keys(token), capsLock: false)
            if case .rescued = outcome {
                XCTFail("rescue-quality: '\(token)' (typed in its own layout) was rescued away")
            }
            if case .ambiguous = outcome {
                XCTFail("rescue-quality: '\(token)' (typed in its own layout) went ambiguous")
            }
        }
    }

    func testKeepSideUkrainianIsNeverConverted() throws {
        let resolver = try resolver(current: Fixture.uk)
        for token in RescueFixture.keepUkrainian {
            let outcome = resolver.evaluate(keys: Fixture.keysForCyrillic(token, lang: "uk"),
                                            capsLock: false)
            if case .rescued = outcome {
                XCTFail("rescue-quality: '\(token)' (typed in its own layout) was rescued away")
            }
            if case .ambiguous = outcome {
                XCTFail("rescue-quality: '\(token)' (typed in its own layout) went ambiguous")
            }
        }
    }

    // MARK: rescue side — measured recall

    func testRescueRecallLatinToCyrillic() throws {
        let resolver = try resolver(current: Fixture.en)
        var hits = 0
        var misses: [String] = []
        for (typed, expectedUk) in RescueFixture.rescueLatinToCyrillic {
            let outcome = resolver.evaluate(keys: Fixture.keys(typed), capsLock: false)
            switch outcome {
            case .rescued(let d) where d.converted == expectedUk:
                hits += 1
            case .ambiguous(_, let winners)
                where winners.contains(where: { $0.lang == "uk" && $0.converted == expectedUk }):
                hits += 1
            case .convert(let d) where d.converted == expectedUk:
                hits += 1   // the dictionary got there first — even better
            default:
                misses.append("\(typed)→\(expectedUk) got \(outcome)")
            }
        }
        let total = RescueFixture.rescueLatinToCyrillic.count
        print(String(format: "rescue-quality: latin→cyrillic recall %.2f (%d/%d)%@",
                     Double(hits) / Double(total), hits, total,
                     misses.isEmpty ? "" : " — missed: \(misses)"))
        XCTAssertGreaterThanOrEqual(Double(hits) / Double(total), RescueFixture.minRescueRecall)
    }

    func testRescueRecallCyrillicToLatin() throws {
        let resolver = try resolver(current: Fixture.uk)
        var hits = 0
        var misses: [String] = []
        for (typedUk, expectedEn) in RescueFixture.rescueCyrillicToLatin {
            let outcome = resolver.evaluate(keys: Fixture.keysForCyrillic(typedUk, lang: "uk"),
                                            capsLock: false)
            switch outcome {
            case .rescued(let d) where d.converted == expectedEn:
                hits += 1
            case .convert(let d) where d.converted == expectedEn:
                hits += 1
            default:
                misses.append("\(typedUk)→\(expectedEn) got \(outcome)")
            }
        }
        let total = RescueFixture.rescueCyrillicToLatin.count
        print(String(format: "rescue-quality: cyrillic→latin recall %.2f (%d/%d)%@",
                     Double(hits) / Double(total), hits, total,
                     misses.isEmpty ? "" : " — missed: \(misses)"))
        XCTAssertGreaterThanOrEqual(Double(hits) / Double(total), RescueFixture.minRescueRecall)
    }
}

#endif

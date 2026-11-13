#if canImport(AppKit)
import XCTest
@testable import Switcher3wCore

/// The four phrase corrections of the 28 Oct – 13 Nov 2026 field log that left a word behind, replayed
/// on the real US and Ukrainian layouts with the decisions the log recorded for each word. Ukrainian
/// typed on the English layout; the held words converted, and the words between them that were "not a
/// word in any installed language" (or a single letter) stayed in Latin — `Це все, xbv z …`.
///
/// The word that triggered each correction is not in the log (it never records what was typed), and it
/// is not part of the segment the correction rewrites, so it is left out.
@MainActor
final class WordsLeftBehindTests: XCTestCase {

    enum Seen { case held, unrecognised }

    static let us = "com.apple.keylayout.US"
    static let uk = "com.apple.keylayout.Ukrainian-PC"

    func replay(_ words: [(String, Seen)], file: StaticString = #filePath, line: UInt = #line) throws -> String? {
        let catalog = LanguageCombinationTests.Catalog(["en", "uk"], current: "en")
        try XCTSkipUnless(LanguageCombinationTests.table(Self.us) != nil
                          && LanguageCombinationTests.table(Self.uk) != nil, "US or Ukrainian-PC not installed")
        let tracker = PhraseTracker { keys, id in catalog.render(keys, layoutID: id) }
        for (typed, seen) in words {
            let keys = try XCTUnwrap(LanguageCombinationTests.keys(for: typed, on: Self.us), typed, file: file, line: line)
            tracker.record(keys: keys, shownText: typed, spacesAfter: 1,
                           kind: seen == .held ? .defaulted(lang: "en") : .unrecognised(lang: "en"))
        }
        return tracker.correction(toLang: "uk", layoutID: Self.uk)?.newSegment
    }

    func test2026_11_10_aLoneLetter() throws {
        XCTAssertEqual(try replay([("yt", .held), ("nt", .held), ("oj,", .held), ("z", .unrecognised)]),
                       "не те щоб я ")
    }

    func test2026_11_11_aLoneLetter() throws {
        XCTAssertEqual(try replay([("nf", .held), ("ys?", .held), ("d", .unrecognised)]),
                       "та ні, в ")
    }

    func test2026_11_11_aMissingShortWordAndJargon() throws {
        XCTAssertEqual(try replay([(",j", .held), ("dsy", .unrecognised), ("ukj,fk", .unrecognised)]),
                       "бо він глобал ")
    }

    func test2026_11_13_chimYa() throws {
        XCTAssertEqual(try replay([("Wt", .held), ("dct?", .held), ("xbv", .unrecognised), ("z", .unrecognised)]),
                       "Це все, чим я ")
    }
}
#endif

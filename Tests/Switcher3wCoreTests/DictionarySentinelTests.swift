import XCTest
@testable import Switcher3wCore

/// The canary sentinel: a lying dictionary must sit out of detection, a healthy one must not
/// notice the guard, and recovery must be automatic. Time is driven by hand.
@MainActor
final class DictionarySentinelTests: XCTestCase {

    /// A dictionary whose truthfulness the test scripts: `mode` decides how it answers.
    private final class ScriptedDictionary: DictionaryValidating {
        enum Mode { case honest, acceptAll, rejectAll }
        var mode: Mode = .honest
        var words: Set<String> = ["привіт"]
        private(set) var queryCount = 0

        func isAvailable(_ lang: String) -> Bool { true }
        func isValidWord(_ word: String, lang: String) -> Bool {
            queryCount += 1
            switch mode {
            case .honest:    return words.contains(word)
            case .acceptAll: return true
            case .rejectAll: return false
            }
        }
    }

    private var clock = Date(timeIntervalSince1970: 1_000_000)

    private func makeSentinel(_ dict: ScriptedDictionary) -> DictionarySentinel {
        DictionarySentinel(wrapping: dict,
                           canaries: ["uk": .init(word: "привіт", mash: "нзукжз")],
                           probeInterval: 60, cooldown: 60,
                           now: { self.clock })
    }

    func testHealthyDictionaryPassesThrough() {
        let dict = ScriptedDictionary()
        let sentinel = makeSentinel(dict)
        XCTAssertTrue(sentinel.isAvailable("uk"))
        XCTAssertTrue(sentinel.isValidWord("привіт", lang: "uk"))
        XCTAssertFalse(sentinel.isValidWord("нзукжз", lang: "uk"))
    }

    func testAcceptAllEpisodeQuarantines() {
        let dict = ScriptedDictionary()
        dict.mode = .acceptAll
        let sentinel = makeSentinel(dict)
        XCTAssertFalse(sentinel.isAvailable("uk"), "a dictionary that validates mash must sit out")
    }

    func testRejectAllEpisodeQuarantines() {
        let dict = ScriptedDictionary()
        dict.mode = .rejectAll
        let sentinel = makeSentinel(dict)
        XCTAssertFalse(sentinel.isAvailable("uk"), "a dictionary that rejects 'привіт' must sit out")
    }

    func testQuarantineHoldsThroughCooldownThenRecovers() {
        let dict = ScriptedDictionary()
        dict.mode = .rejectAll
        let sentinel = makeSentinel(dict)
        XCTAssertFalse(sentinel.isAvailable("uk"))

        // Healed immediately — but the cooldown still holds: no per-query re-probing.
        dict.mode = .honest
        clock.addTimeInterval(30)
        XCTAssertFalse(sentinel.isAvailable("uk"))

        // Past the cooldown the next query re-probes and recovers.
        clock.addTimeInterval(31)
        XCTAssertTrue(sentinel.isAvailable("uk"))
    }

    func testProbesStayOffTheHotPath() {
        let dict = ScriptedDictionary()
        let sentinel = makeSentinel(dict)
        XCTAssertTrue(sentinel.isAvailable("uk"))   // first use: one probe (two queries)
        let afterProbe = dict.queryCount
        for _ in 0..<50 { _ = sentinel.isAvailable("uk") }
        XCTAssertEqual(dict.queryCount, afterProbe, "a trusted language must not re-probe per query")

        // …until the trust interval lapses.
        clock.addTimeInterval(61)
        _ = sentinel.isAvailable("uk")
        XCTAssertEqual(dict.queryCount, afterProbe + 2, "one re-probe after the interval, no more")
    }

    func testLanguageWithoutCanaryIsNotGuarded() {
        let dict = ScriptedDictionary()
        dict.mode = .acceptAll
        let sentinel = makeSentinel(dict)
        XCTAssertTrue(sentinel.isAvailable("en"), "no canary configured — nothing to verify")
    }
}

/// The single-verdict rule: one decision may ask the dictionary about a word at most once, so a
/// checker that flip-flops mid-evaluation cannot split the outcome against the logged dump.
@MainActor
final class SingleVerdictTests: XCTestCase {

    /// Valid on the FIRST query for each word, invalid on every later one — the exact shape of
    /// the flip-flop that produced "dump says VALID, outcome says no winner" in the field.
    private final class FlipFlopDictionary: DictionaryValidating {
        var words: Set<String>
        private var seen: Set<String> = []

        init(_ words: Set<String>) { self.words = words }

        func isAvailable(_ lang: String) -> Bool { true }
        func isValidWord(_ word: String, lang: String) -> Bool {
            guard words.contains(word) else { return false }
            return seen.insert(word).inserted   // true the first time, false after
        }
    }

    func testOutcomeFollowsTheFirstVerdict() {
        let dict = FlipFlopDictionary(["привіт"])
        let resolver = NWayResolver(catalog: Fixture.catalog(current: Fixture.en),
                                    dict: dict, exceptions: FakeExceptions())
        // "ghbdsn" renders to привіт in uk and ru; the first (candidate-building) query says
        // valid, and any second query would say invalid. The decision must convert regardless.
        let outcome = resolver.evaluate(keys: Fixture.keys("ghbdsn"), capsLock: false)
        switch outcome {
        case .convert, .ambiguous:
            break   // the first verdict won — uk (or uk+ru) converted
        default:
            XCTFail("a flip-flopping dictionary split the decision: \(outcome)")
        }
    }
}

import Foundation

/// Guards the resolver against a dictionary that has stopped telling the truth.
///
/// `NSSpellChecker` goes through transient episodes of answering wrong in both directions —
/// rejecting `привіт`, validating keyboard mash (`Тфефдшу`) — for minutes at a time
/// (log evidence 2026-07-20…08-31; also reproduced once across a whole test-suite run). A
/// precision-first app cannot act on an oracle in that state: a false "invalid" silently eats
/// conversions word by word, and a false "valid" converts a name into Cyrillic noise.
///
/// The sentinel wraps any `DictionaryValidating` and probes each language with two canaries —
/// a common word that must validate and mash that must not — on the language's first use, then
/// at most once per `probeInterval`. A failed probe QUARANTINES the language: it reports as
/// unavailable, the resolver treats it as nonexistent, and auto-conversion degrades to doing
/// nothing rather than doing wrong. A later probe that passes lifts the quarantine. Both events
/// log unconditionally — a suspended dictionary is the app "not working" from the user's chair,
/// exactly the failure class the debug-log gate must never hide.
///
/// The probes live on `isAvailable`, which the resolver consults once per language per decision
/// — not per candidate query — so a healthy dictionary pays one timestamp comparison.
@MainActor
public final class DictionarySentinel: DictionaryValidating {

    /// What must be true of a healthy dictionary for this language.
    public struct Canary {
        /// A common word of the language; a dictionary that rejects it is broken.
        public let word: String
        /// Keyboard mash; a dictionary that accepts it is not checking anything.
        public let mash: String

        public init(word: String, mash: String) {
            self.word = word
            self.mash = mash
        }
    }

    /// How long a passed probe is trusted before the language is probed again.
    public let probeInterval: TimeInterval
    /// How long a quarantine lasts before the next query is allowed to re-probe.
    public let cooldown: TimeInterval

    private let wrapped: DictionaryValidating
    private let canaries: [String: Canary]
    private let now: () -> Date

    private enum Health {
        case trusted(until: Date)
        case quarantined(until: Date)
    }
    private var health: [String: Health] = [:]

    public init(wrapping wrapped: DictionaryValidating,
                canaries: [String: Canary],
                probeInterval: TimeInterval = 60,
                cooldown: TimeInterval = 60,
                now: @escaping () -> Date = Date.init) {
        self.wrapped = wrapped
        self.canaries = canaries
        self.probeInterval = probeInterval
        self.cooldown = cooldown
        self.now = now
    }

    public func isAvailable(_ lang: String) -> Bool {
        guard wrapped.isAvailable(lang) else { return false }
        guard let canary = canaries[lang] else { return true }   // no canary — nothing to verify

        switch health[lang] {
        case .trusted(let until) where now() < until:
            return true
        case .quarantined(let until) where now() < until:
            return false
        default:
            return probe(lang, canary)
        }
    }

    public func isValidWord(_ word: String, lang: String) -> Bool {
        wrapped.isValidWord(word, lang: lang)
    }

    public func alphabet(_ lang: String) -> String { wrapped.alphabet(lang) }
    public func vowels(_ lang: String) -> String { wrapped.vowels(lang) }

    /// Ask the two canary questions and record the verdict. Returns whether the language is
    /// usable right now.
    private func probe(_ lang: String, _ canary: Canary) -> Bool {
        let wordOK = wrapped.isValidWord(canary.word, lang: lang)
        let mashOK = !wrapped.isValidWord(canary.mash, lang: lang)
        let healthy = wordOK && mashOK

        let wasQuarantined: Bool
        if case .quarantined = health[lang] { wasQuarantined = true } else { wasQuarantined = false }

        if healthy {
            health[lang] = .trusted(until: now().addingTimeInterval(probeInterval))
            if wasQuarantined {
                CoreLog.alert("dict-sentinel: \(lang) recovered — canaries answer correctly again")
            }
        } else {
            health[lang] = .quarantined(until: now().addingTimeInterval(cooldown))
            // Name the direction: an accept-all episode and a reject-all episode look identical
            // to the user (nothing converts / wrong things convert) and need this line to differ.
            let reason = wordOK ? "accepts keyboard mash ('\(canary.mash)')"
                                : "rejects a common word ('\(canary.word)')"
            CoreLog.alert("dict-sentinel: \(lang) QUARANTINED for \(Int(cooldown))s — dictionary \(reason); "
                          + "no conversions will use this language until it answers correctly")
        }
        return healthy
    }
}

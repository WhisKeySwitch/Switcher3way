import Foundation

/// Phrase-level language memory for auto-conversion (phrase-aware-ambiguity).
///
/// A "phrase" is the run of evaluated words since the last hard reset (Enter/Tab/arrows/
/// mouse click/app or focus switch — the same events that reset the word buffer).
/// Words whose uk/ru ambiguity was resolved by the preference are remembered as `defaulted`;
/// when a later word is valid in exactly ONE language, the defaulted words of other languages
/// are re-converted to it in a single segment replacement. Precision-first: the tracker
/// resets on anything it can't account for exactly, and a phrase locked to one language
/// never corrects toward another.
@MainActor
final class PhraseTracker {
    enum WordKind: Equatable {
        case defaulted(lang: String)  // ambiguity resolved by preference/lock — retro-correctable
        case locked(lang: String)     // valid in exactly one language — locks the phrase
        case neutral                  // kept / valid as typed — reproduced verbatim in corrections
    }

    struct PhraseWord {
        let keys: [TypedKey]
        var shownText: String   // what this word looks like on screen right now
        var spacesAfter: Int
        var kind: WordKind
    }

    /// Maximum characters a correction may erase — bounds worst-case erase chains.
    static let maxCorrectionLength = 200

    private(set) var words: [PhraseWord] = []
    /// Bumped on every reset. Retype completions run asynchronously; a completion whose
    /// captured generation no longer matches means a reset (click/Enter/focus change) raced
    /// it — the screen has moved on and the pending record/confirm must be dropped.
    private(set) var generation = 0

    /// The language the phrase is locked to (first exactly-one-language word), nil if none yet.
    var lockedLang: String? {
        for w in words { if case .locked(let lang) = w.kind { return lang } }
        return nil
    }

    func reset() {
        if !words.isEmpty { rslog("phrase: reset (\(words.count) word(s))") }
        words = []
        generation &+= 1
    }

    /// Records an evaluated word. Pass `ifGeneration` from an async completion so a record
    /// that lost the race against a reset is dropped instead of corrupting the phrase.
    func record(keys: [TypedKey], shownText: String, spacesAfter: Int,
                kind: WordKind, ifGeneration gen: Int? = nil) {
        if let gen, gen != generation {
            rslog("phrase: record dropped (stale generation)")
            return
        }
        words.append(PhraseWord(keys: keys, shownText: shownText, spacesAfter: spacesAfter, kind: kind))
    }

    /// An extra space arrived after the last recorded word (no new word between) — keeps the
    /// segment character math exact for multi-space runs.
    func noteExtraSpace() {
        guard !words.isEmpty else { return }
        words[words.count - 1].spacesAfter += 1
    }

    /// A planned retro-correction: the on-screen segment to erase, its replacement, and the
    /// updated word records to store once the replacement succeeded.
    struct Correction {
        let oldSegment: String
        let newSegment: String
        let firstIndex: Int
        let correctedWords: [PhraseWord]
    }

    /// Builds the correction toward `lang` (rendered through the layout `layoutID`): the
    /// segment from the first defaulted-to-another-language word through the last recorded
    /// word. Defaulted words re-render their keystrokes; neutral/locked words are reproduced
    /// verbatim. nil — nothing defaulted to another language, the phrase is locked to a
    /// conflicting language, a re-render failed, or the segment exceeds the length cap.
    func correction(toLang lang: String, layoutID: String) -> Correction? {
        if let locked = lockedLang, locked != lang {
            rslog("phrase: contradictory (locked \(locked), new \(lang)) — no correction")
            return nil
        }
        guard let first = words.firstIndex(where: {
            if case .defaulted(let l) = $0.kind { return l != lang }
            return false
        }) else { return nil }

        var old = "", new = ""
        var corrected: [PhraseWord] = []
        for index in first..<words.count {
            var word = words[index]
            let spaces = String(repeating: " ", count: word.spacesAfter)
            old += word.shownText + spaces
            if case .defaulted(let l) = word.kind, l != lang {
                guard let rerendered = NWayResolver.render(keys: word.keys, layoutID: layoutID) else {
                    rslog("phrase: re-render failed — no correction")
                    return nil
                }
                word.shownText = rerendered
                word.kind = .defaulted(lang: lang)
            }
            new += word.shownText + spaces
            corrected.append(word)
        }
        guard old.count <= Self.maxCorrectionLength else {
            rslog("phrase: correction segment too long (\(old.count) chars) — skipped")
            return nil
        }
        return Correction(oldSegment: old, newSegment: new, firstIndex: first, correctedWords: corrected)
    }

    /// Commits a successful correction to the memory (call from the retype success completion,
    /// with the generation captured when the correction was planned).
    func confirm(_ correction: Correction, ifGeneration gen: Int) {
        guard gen == generation else {
            rslog("phrase: confirm dropped (stale generation)")
            return
        }
        guard correction.firstIndex + correction.correctedWords.count == words.count else {
            reset()   // the phrase changed shape while the retype ran — memory is unreliable
            return
        }
        words.replaceSubrange(correction.firstIndex..., with: correction.correctedWords)
        rslog("phrase: correction committed (\(correction.correctedWords.count) word(s))")
    }
}

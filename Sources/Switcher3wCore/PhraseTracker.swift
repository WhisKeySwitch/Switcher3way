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
public final class PhraseTracker {

    /// Re-renders a word's keystrokes into a given layout. Injected rather than reached for
    /// statically, so the tracker is assertable without layouts, dictionaries, or the app.
    private let render: (_ keys: [TypedKey], _ layoutID: String) -> String?

    public init(render: @escaping (_ keys: [TypedKey], _ layoutID: String) -> String?) {
        self.render = render
    }

    public enum WordKind: Equatable {
        case defaulted(lang: String)  // ambiguity resolved by preference/lock — retro-correctable
        case locked(lang: String)     // valid in exactly one language — locks the phrase
        case neutral                  // kept / valid as typed — reproduced verbatim in corrections
    }

    public struct PhraseWord {
        public let keys: [TypedKey]
        public var shownText: String   // what this word looks like on screen right now
        public var spacesAfter: Int
        public var kind: WordKind
    }

    /// Maximum characters a correction may erase — bounds worst-case erase chains.
    public static let maxCorrectionLength = 200

    public private(set) var words: [PhraseWord] = []
    /// Bumped on every reset. Retype completions run asynchronously; a completion whose
    /// captured generation no longer matches means a reset (click/Enter/focus change) raced
    /// it — the screen has moved on and the pending record/confirm must be dropped.
    public private(set) var generation = 0

    /// The language the phrase is locked to (first exactly-one-language word), nil if none yet.
    public var lockedLang: String? {
        for w in words { if case .locked(let lang) = w.kind { return lang } }
        return nil
    }

    public func reset() {
        if !words.isEmpty { CoreLog.write("phrase: reset (\(words.count) word(s))") }
        words = []
        generation &+= 1
    }

    /// Records an evaluated word. Pass `ifGeneration` from an async completion so a record
    /// that lost the race against a reset is dropped instead of corrupting the phrase.
    public func record(keys: [TypedKey], shownText: String, spacesAfter: Int,
                kind: WordKind, ifGeneration gen: Int? = nil) {
        if let gen, gen != generation {
            CoreLog.write("phrase: record dropped (stale generation)")
            return
        }
        words.append(PhraseWord(keys: keys, shownText: shownText, spacesAfter: spacesAfter, kind: kind))
    }

    /// An extra space arrived after the last recorded word (no new word between) — keeps the
    /// segment character math exact for multi-space runs.
    public func noteExtraSpace() {
        guard !words.isEmpty else { return }
        words[words.count - 1].spacesAfter += 1
    }

    /// A planned retro-correction: the on-screen segment to erase, its replacement, and the
    /// updated word records to store once the replacement succeeded.
    public struct Correction {
        public let oldSegment: String
        public let newSegment: String
        public let firstIndex: Int
        public let correctedWords: [PhraseWord]
    }

    /// Builds the correction toward `lang` (rendered through the layout `layoutID`): the
    /// segment from the first defaulted-to-another-language word through the last recorded
    /// word. Defaulted words re-render their keystrokes; neutral/locked words are reproduced
    /// verbatim. nil — nothing defaulted to another language, the phrase is locked to a
    /// conflicting language, a re-render failed, or the segment exceeds the length cap.
    public func correction(toLang lang: String, layoutID: String) -> Correction? {
        if let locked = lockedLang, locked != lang {
            CoreLog.write("phrase: contradictory (locked \(locked), new \(lang)) — no correction")
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
                guard let rerendered = render(word.keys, layoutID) else {
                    CoreLog.write("phrase: re-render failed — no correction")
                    return nil
                }
                word.shownText = rerendered
                word.kind = .defaulted(lang: lang)
            }
            new += word.shownText + spaces
            corrected.append(word)
        }
        guard old.count <= Self.maxCorrectionLength else {
            CoreLog.write("phrase: correction segment too long (\(old.count) chars) — skipped")
            return nil
        }
        return Correction(oldSegment: old, newSegment: new, firstIndex: first, correctedWords: corrected)
    }

    /// Commits a successful correction to the memory (call from the retype success completion,
    /// with the generation captured when the correction was planned).
    public func confirm(_ correction: Correction, ifGeneration gen: Int) {
        guard gen == generation else {
            CoreLog.write("phrase: confirm dropped (stale generation)")
            return
        }
        guard correction.firstIndex + correction.correctedWords.count == words.count else {
            reset()   // the phrase changed shape while the retype ran — memory is unreliable
            return
        }
        words.replaceSubrange(correction.firstIndex..., with: correction.correctedWords)
        CoreLog.write("phrase: correction committed (\(correction.correctedWords.count) word(s))")
    }
}

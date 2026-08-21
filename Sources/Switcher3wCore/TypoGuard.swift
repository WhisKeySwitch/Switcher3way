import Foundation

/// Tells a fumbled key apart from the wrong keyboard.
///
/// The resolver's original reasoning was: this is not a word here, but it is a word over there, so
/// the layout must be wrong. That reasoning has no way to express the far more common explanation —
/// you are typing your own language and you mistyped — and so it converts typos. A Ukrainian user
/// abandoned the Windows build over it: every fumble threw a word into English and dragged the
/// layout with it, leaving a long document with English debris scattered through it. The same
/// reasoning, and so the same defect, is here.
///
/// The missing evidence is cheap to get. If the language you are already typing in holds a word one
/// keystroke away from what you typed, the simple explanation is that you missed the key — not that
/// you silently changed keyboards for one word and changed back. That is what this measures.
///
/// Edits considered are the ones fingers actually make: a dropped letter, a doubled or inserted
/// letter, a wrong letter, and two letters swapped (Damerau–Levenshtein distance one).
///
/// A port of `TypoGuard` in the Windows core, deliberately line-for-line comparable with it.
@MainActor
public enum TypoGuard {

    /// Does `lang` hold a real word exactly one edit away from `typed`?
    ///
    /// Returns false when the validator cannot name the language's letters, so a dictionary that
    /// does not expose an alphabet degrades to the old behaviour rather than vetoing everything.
    public static func nearMiss(_ typed: String, lang: String, dict: DictionaryValidating) -> Bool {
        let chars = Array(typed)
        guard chars.count >= 2 else { return false }

        // A dropped letter — and, by the same test, a doubled one: "програмаа" minus a character is
        // "програма", so both fumbles are caught here.
        for i in chars.indices {
            var v = chars
            v.remove(at: i)
            if dict.isValidWord(String(v), lang: lang) { return true }
        }

        // Two adjacent letters swapped.
        for i in 0..<(chars.count - 1) {
            var v = chars
            v.swapAt(i, i + 1)
            if dict.isValidWord(String(v), lang: lang) { return true }
        }

        // A wrong or extra letter. This is the part that needs the alphabet, and it is why the
        // check is only consulted for words long enough for the answer to mean something: the
        // number of neighbours tried here grows with both the word and the alphabet.
        let alphabet = Array(dict.alphabet(lang))
        guard !alphabet.isEmpty else { return false }
        for c in alphabet {
            for i in 0...chars.count {
                var v = chars
                v.insert(c, at: i)
                if dict.isValidWord(String(v), lang: lang) { return true }
            }
            for i in chars.indices where chars[i] != c {
                var v = chars
                v[i] = c
                if dict.isValidWord(String(v), lang: lang) { return true }
            }
        }
        return false
    }
}

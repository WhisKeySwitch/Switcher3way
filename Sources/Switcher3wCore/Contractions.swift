import Foundation

/// Which English apostrophe words are words.
///
/// `NSSpellChecker` judges an apostrophe word piece by piece, so it accepts `fr'd`, `w'go`, `l'ed`,
/// `em'e` and `me''e`. Nobody types those — but the Bulgarian layout puts `ч` on the US apostrophe
/// key, so Bulgarian typed with the English layout active, and Bulgarian typos, render as exactly
/// such strings. Measured on en+bg: 8 of the 13 Bulgarian typos that converted into English were
/// these. Once contractions were let through the soft gates (1.6.0), the dictionary's verdict on
/// them was believed as it stood.
///
/// English contractions are a small closed grammar, so the rule is stated rather than learnt:
/// `'s` after anything (possessive, `it's`), `n't` after its verb, and `'d 'll 're 've 'm` after the
/// pronouns that take them — plus the few fixed words that fit none of those. Only English is
/// judged; Ukrainian `п'ять` and French `l'eau` are untouched.
public enum Contractions {

    static let pronouns: Set<String> = [
        "i", "you", "he", "she", "it", "we", "they", "who", "that", "there", "what", "where",
        "how", "here", "why", "when", "this",
    ]

    static let fixed: Set<String> = ["o'clock", "y'all", "ma'am", "ne'er", "e'er", "rock'n'roll", "'cause"]

    /// Is the dictionary's verdict on this (lower-cased letter core) believable? True for anything
    /// without an apostrophe, and for anything not English.
    public static func admits(_ core: String, lang: String) -> Bool {
        guard lang.hasPrefix("en") else { return true }
        let word = core.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
        guard word.contains("'") else { return true }
        if fixed.contains(word) { return true }
        let parts = word.split(separator: "'", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, let stem = parts.first, let clitic = parts.last, !stem.isEmpty else { return false }
        switch clitic {
        case "s":                    return true
        case "t":                    return stem.count >= 2 && stem.hasSuffix("n")
        case "m":                    return stem == "i"
        case "d", "ll", "re", "ve":  return pronouns.contains(stem)
        default:                     return false
        }
    }
}

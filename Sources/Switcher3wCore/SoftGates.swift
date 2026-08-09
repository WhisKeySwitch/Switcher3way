import Foundation

/// The cheap vetoes applied before any dictionary lookup: we let a word into the detector only if
/// it is a "real" word, and not a single letter, an acronym, or code. Precision-first — on doubt,
/// false. Shared by the 2-way path (`LayoutDetector.decide`) and the N-way resolver.
public enum SoftGates {

    public static func passes(_ typed: String, capsLock: Bool) -> Bool {
        guard typed.count >= 2 else { return false }                  // 1 letter (я/a/i/і): hopelessly ambiguous between layouts
        guard typed.allSatisfy({ $0.isLetter }) else { return false } // digits/punctuation/URL/code/email
        // Applied whatever the shift state: a token drawn from two alphabets is a code identifier,
        // and Caps Lock has nothing to do with alphabets. This veto used to share a function with
        // the camelCase one below and was skipped along with it — so `приvit` passed the gates
        // under Caps Lock, which nobody chose.
        if isMixedScript(typed) { return false }
        // Under Caps Lock all text is UPPERCASE, so neither "is it an acronym" nor "does it carry
        // an internal capital" can tell us anything — that is the whole reason for this exemption.
        if !capsLock {
            if isAllCaps(typed) { return false }                      // acronyms
            if hasInternalCapital(typed) { return false }             // camelCase / PascalCase
        }
        return true
    }

    static func isAllCaps(_ s: String) -> Bool {
        s == s.uppercased() && s != s.lowercased()
    }

    /// An internal capital — camelCase/PascalCase, almost always code rather than a word.
    /// Meaningless while Caps Lock is down, which is why `passes` gates it on that.
    static func hasInternalCapital(_ s: String) -> Bool {
        for (i, c) in s.enumerated() where i > 0 && c.isUppercase { return true }
        return false
    }

    /// Latin and Cyrillic letters in the same token → code, not a word. Independent of letter case,
    /// so unlike the two vetoes above this one is applied in every shift state.
    static func isMixedScript(_ s: String) -> Bool {
        var hasLatin = false, hasCyrillic = false
        for u in s.unicodeScalars {
            switch u.value {
            case 0x41...0x5A, 0x61...0x7A: hasLatin = true
            case 0x0400...0x04FF: hasCyrillic = true
            default: break
            }
        }
        return hasLatin && hasCyrillic
    }

    /// The contiguous range of `chars` with leading/trailing characters that satisfy `drop` removed.
    static func coreRange(count: Int, drop: (Int) -> Bool) -> Range<Int> {
        var lo = 0, hi = count
        while lo < hi && drop(lo) { lo += 1 }
        while hi > lo && drop(hi - 1) { hi -= 1 }
        return lo..<hi
    }

    /// The word's letter core: the text with leading/trailing non-letters trimmed. Validation runs
    /// on the core so a trailing "!" or a leading "(" doesn't hide an otherwise-valid word, while
    /// the whole token is still re-rendered on output.
    public static func letterCore(_ chars: [Character]) -> String {
        String(chars[coreRange(count: chars.count) { !chars[$0].isLetter }])
    }

    public static func letterCore(_ s: String) -> String {
        letterCore(Array(s))
    }
}

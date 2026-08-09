import Foundation

/// The cheap vetoes applied before any dictionary lookup: we let a word into the detector only if
/// it is a "real" word, and not a single letter, an acronym, or code. Precision-first — on doubt,
/// false. Shared by the 2-way path (`LayoutDetector.decide`) and the N-way resolver.
public enum SoftGates {

    public static func passes(_ typed: String, capsLock: Bool) -> Bool {
        guard typed.count >= 2 else { return false }                  // 1 letter (я/a/i/і): hopelessly ambiguous between layouts
        guard typed.allSatisfy({ $0.isLetter }) else { return false } // digits/punctuation/URL/code/email
        // Under Caps Lock all text is UPPERCASE — this is NOT an acronym and NOT camelCase,
        // so these two vetoes are applied only when Caps Lock is off.
        if !capsLock {
            if isAllCaps(typed) { return false }                      // acronyms
            if looksLikeCodeIdentifier(typed) { return false }        // camelCase / mixed alphabets
        }
        return true
    }

    static func isAllCaps(_ s: String) -> Bool {
        s == s.uppercased() && s != s.lowercased()
    }

    /// Looks like a code identifier: an internal capital (camelCase/PascalCase)
    /// or a mix of Latin and Cyrillic in one token → almost always code, not a word.
    static func looksLikeCodeIdentifier(_ s: String) -> Bool {
        for (i, c) in s.enumerated() where i > 0 && c.isUppercase { return true }
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

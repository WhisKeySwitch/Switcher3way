namespace Switcher3way.Core;

/// <summary>
/// Precision-first soft vetoes and letter-core trimming, shared by the auto and manual paths.
/// A faithful port of the macOS <c>LayoutDetector.passesSoftGates</c> + <c>NWayResolver.letterCore</c>.
/// A word enters detection only if it is a "real" word — not a single letter, an acronym, or code.
/// </summary>
public static class SoftGates
{
    /// <summary>
    /// True if <paramref name="typed"/> may be considered for conversion. Precision-first: on doubt,
    /// false. Callers pass the letter core (edge punctuation already trimmed).
    /// </summary>
    public static bool PassesSoftGates(string typed, bool capsLock)
    {
        if (typed.Length < 2) return false;                     // 1 letter (я/a/i/і): hopelessly ambiguous
        foreach (var ch in typed)
            if (!char.IsLetter(ch)) return false;               // digits/punctuation/URL/code/email
        // Under Caps Lock everything is UPPERCASE — not an acronym, not camelCase — so skip these two.
        if (!capsLock)
        {
            if (IsAllCaps(typed)) return false;                 // acronyms
            if (LooksLikeCodeIdentifier(typed)) return false;   // camelCase / mixed alphabets
        }
        return true;
    }

    private static bool IsAllCaps(string s) =>
        s == s.ToUpperInvariant() && s != s.ToLowerInvariant();

    /// <summary>
    /// Looks like a code identifier: an internal capital (camelCase/PascalCase) or a mix of Latin
    /// and Cyrillic in one token → almost always code, not a word.
    /// </summary>
    private static bool LooksLikeCodeIdentifier(string s)
    {
        for (int i = 1; i < s.Length; i++)
            if (char.IsUpper(s[i])) return true;

        bool hasLatin = false, hasCyrillic = false;
        foreach (var ch in s)
        {
            int u = ch;
            if ((u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A)) hasLatin = true;
            else if (u >= 0x0400 && u <= 0x04FF) hasCyrillic = true;
        }
        return hasLatin && hasCyrillic;
    }

    /// <summary>The word's letter core: the string with leading/trailing non-letters trimmed.</summary>
    public static string LetterCore(string s)
    {
        int lo = 0, hi = s.Length;
        while (lo < hi && !char.IsLetter(s[lo])) lo++;
        while (hi > lo && !char.IsLetter(s[hi - 1])) hi--;
        return s.Substring(lo, hi - lo);
    }
}

namespace Switcher3way.Core;

/// <summary>
/// Tells a fumbled key apart from the wrong keyboard.
///
/// The resolver's original reasoning was: this is not a word here, but it is a word over there, so
/// the layout must be wrong. That reasoning has no way to express the far more common explanation —
/// you are typing your own language and you mistyped — and so it converts typos. A Ukrainian user
/// abandoned the app over it: every fumble threw a word into English and dragged the layout with it,
/// leaving a long document with English debris scattered through it.
///
/// The missing evidence is cheap to get. If the language you are already typing in holds a word one
/// keystroke away from what you typed, the simple explanation is that you missed the key — not that
/// you silently changed keyboards for one word and changed back. That is what this measures.
///
/// Edits considered are the ones fingers actually make: a dropped letter, a doubled or inserted
/// letter, a wrong letter, and two letters swapped (Damerau–Levenshtein distance one).
///
/// Cost, measured on the bundled dictionaries: a hit exits early and costs 0.04–0.6 ms, a miss walks
/// the whole neighbourhood and costs 4–7 ms for a word of eight or nine characters. That asymmetry
/// falls the right way round — a miss is the answer "go ahead and convert", so it is always followed
/// by a rewrite costing hundreds of milliseconds, while a hit (the answer that cancels the work) is
/// the cheap one. It runs on the engine's worker thread, only when a conversion is already on the
/// table, and only for words long enough for it to mean anything.
/// </summary>
public static class TypoGuard
{
    /// <summary>
    /// Does <paramref name="lang"/> hold a real word exactly one edit away from <paramref name="typed"/>?
    ///
    /// Returns false when the validator cannot name the language's letters, so a dictionary that does
    /// not expose an alphabet degrades to the old behaviour rather than silently vetoing everything.
    /// </summary>
    public static bool NearMiss(string typed, string lang, IDictionaryValidator dict)
    {
        if (typed.Length < 2) return false;

        // A dropped letter — and, by the same test, a doubled one: "програмаа" minus a character is
        // "програма", so both fumbles are caught here.
        for (var i = 0; i < typed.Length; i++)
            if (dict.IsValidWord(typed.Remove(i, 1), lang)) return true;

        // Two adjacent letters swapped.
        for (var i = 0; i + 1 < typed.Length; i++)
        {
            var a = typed.ToCharArray();
            (a[i], a[i + 1]) = (a[i + 1], a[i]);
            if (dict.IsValidWord(new string(a), lang)) return true;
        }

        // A wrong or extra letter. This needs the alphabet, and Hunspell's TRY line supplies it in
        // frequency order, so the common substitutions are tried first and the loop usually exits early.
        var alphabet = dict.Alphabet(lang);
        if (alphabet.Length == 0) return false;
        foreach (var c in alphabet)
        {
            var s = c.ToString();
            for (var i = 0; i <= typed.Length; i++)
                if (dict.IsValidWord(typed.Insert(i, s), lang)) return true;
            for (var i = 0; i < typed.Length; i++)
                if (typed[i] != c && dict.IsValidWord(typed.Remove(i, 1).Insert(i, s), lang)) return true;
        }
        return false;
    }
}

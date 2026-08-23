namespace Switcher3way.Core;

/// <summary>
/// One typed key: physical keycode + modifier state. <see cref="Char"/> is set only for
/// characters forwarded through a remote desktop (keycode 0 + char), which render identically in
/// every layout — the N-way path bails out when any key carries one.
/// </summary>
public readonly record struct TypedKey(int KeyCode, bool Shift, bool Caps, char? Char = null);

/// <summary>An installed keyboard layout: an opaque id and its 2-letter language (null if none).</summary>
public sealed record Layout(string Id, string? Lang);

/// <summary>An auto-conversion decision: switch to <see cref="TargetLayoutId"/> and rewrite the word.</summary>
public sealed record Decision(string TargetLayoutId, string Original, string Converted);

/// <summary>One language that validates the typed word (carried when more than one does).</summary>
public sealed record Winner(string Lang, string LayoutId, string Converted);

/// <summary>
/// Full evaluation result of <see cref="NWayResolver.Evaluate"/>. <see cref="Ambiguous"/> carries
/// every validating language so the caller can resolve it by the preferred-language setting / phrase
/// lock (phrase-aware ambiguity); <see cref="NWayResolver.Resolve"/> collapses it for callers that
/// only want the unambiguous case. A closed union — the four nested records are the only cases.
/// </summary>
public abstract record Outcome
{
    private Outcome() { }

    /// <summary>
    /// Leave the text and layout as they are, and say why.
    ///
    /// The reason is not decoration. Most of what this app decides is "do nothing", and a decision to
    /// do nothing is invisible on screen — so without the reason recorded, a guard that is working
    /// perfectly and a guard that is broken produce exactly the same evidence: none. The reason also
    /// carries information the caller acts on, since <see cref="KeepReason.ValidInCurrent"/> is the
    /// strongest signal the app ever gets about what language a phrase is in.
    /// </summary>
    public sealed record Keep(KeepReason Reason = KeepReason.NotAWordAnywhere) : Outcome
    {
        /// <summary>The word is a real word of the language it was typed in.</summary>
        public bool ValidInCurrent => Reason == KeepReason.ValidInCurrent;
    }

    /// <summary>Exactly one target language: switch and rewrite.</summary>
    public sealed record Convert(Decision Decision) : Outcome;

    /// <summary>More than one language validates the word (uk↔ru): the caller applies the policy.</summary>
    public sealed record Ambiguous(string Original, IReadOnlyList<Winner> Winners) : Outcome;

    /// <summary>
    /// The input reads as another language, but on evidence too weak to act on by itself: a word of
    /// two or three letters, where a dictionary hit means almost nothing. Nearly a quarter of all
    /// two-letter Latin strings are in the English dictionary, mostly as abbreviations, so converting
    /// on that alone turns ordinary Ukrainian typos into English debris.
    ///
    /// The caller leaves the text alone and records the keystrokes as defaulted to the current
    /// language, so the next word that does settle the phrase converts this one along with it.
    /// </summary>
    public sealed record Defer(string Original, IReadOnlyList<Winner> Winners) : Outcome;
}

/// <summary>
/// Why a word was left alone. Every one of these is a decision, and every one of them is invisible
/// unless it is written down.
/// </summary>
public enum KeepReason
{
    /// <summary>Not a word in any installed language — ordinary for names, code and typing in progress.</summary>
    NotAWordAnywhere,
    /// <summary>A real word of the language it was typed in. Nothing to fix, and it settles the phrase.</summary>
    ValidInCurrent,
    /// <summary>The current layout or its language could not be determined.</summary>
    NoCurrentLanguage,
    /// <summary>
    /// It reads as another language, but the language being typed holds a word one keystroke away, so
    /// a fumbled key is the simpler explanation. This is the guard that stops typos being converted.
    /// </summary>
    LooksLikeATypo,
    /// <summary>Too short to decide alone, and it disagrees with the language the phrase settled into.</summary>
    PhraseDisagrees,
}

/// <summary>One step of the manual cycle: a target layout and how the input looks in it.</summary>
public sealed record ManualCandidate(string TargetLayoutId, string Converted);

/// <summary>
/// A manual-trigger plan: the original text (rendered in the current layout), the layout active
/// before the first conversion, and the ordered candidates to cycle through.
/// </summary>
public sealed record ManualPlan(string Original, string OriginalLayoutId, IReadOnlyList<ManualCandidate> Candidates);

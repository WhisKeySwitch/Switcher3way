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
/// only want the unambiguous case. A closed union — the three nested records are the only cases.
/// </summary>
public abstract record Outcome
{
    private Outcome() { }

    /// <summary>Leave the text and layout as they are.</summary>
    public sealed record Keep : Outcome;

    /// <summary>Exactly one target language: switch and rewrite.</summary>
    public sealed record Convert(Decision Decision) : Outcome;

    /// <summary>More than one language validates the word (uk↔ru): the caller applies the policy.</summary>
    public sealed record Ambiguous(string Original, IReadOnlyList<Winner> Winners) : Outcome;
}

/// <summary>One step of the manual cycle: a target layout and how the input looks in it.</summary>
public sealed record ManualCandidate(string TargetLayoutId, string Converted);

/// <summary>
/// A manual-trigger plan: the original text (rendered in the current layout), the layout active
/// before the first conversion, and the ordered candidates to cycle through.
/// </summary>
public sealed record ManualPlan(string Original, string OriginalLayoutId, IReadOnlyList<ManualCandidate> Candidates);

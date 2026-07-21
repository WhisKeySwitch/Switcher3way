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

/// <summary>One step of the manual cycle: a target layout and how the input looks in it.</summary>
public sealed record ManualCandidate(string TargetLayoutId, string Converted);

/// <summary>
/// A manual-trigger plan: the original text (rendered in the current layout), the layout active
/// before the first conversion, and the ordered candidates to cycle through.
/// </summary>
public sealed record ManualPlan(string Original, string OriginalLayoutId, IReadOnlyList<ManualCandidate> Candidates);

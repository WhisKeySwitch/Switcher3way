namespace Switcher3way.Core;

/// <summary>
/// Phrase-level language memory for auto-conversion (phrase-aware ambiguity). A faithful port of the
/// macOS <c>PhraseTracker</c>.
///
/// A "phrase" is the run of evaluated words since the last hard reset (Enter/Tab/arrows/mouse click/
/// app or focus switch — the same events that reset the word buffer). Words whose uk/ru ambiguity was
/// resolved by the preference are remembered as <see cref="WordKind.Defaulted"/>; when a later word is
/// valid in exactly one language, the defaulted words of other languages are re-converted to it in a
/// single segment replacement. Precision-first: the tracker resets on anything it can't account for
/// exactly, and a phrase locked to one language never corrects toward another.
///
/// Not thread-safe by design — the Windows engine mutates it only on its single worker thread
/// (word events and resets are both marshaled there), so no locking is needed.
/// </summary>
public sealed class PhraseTracker
{
    /// <summary>Renders a word's keys through a layout id (backed by <c>NWayResolver.Render</c>).</summary>
    public delegate string? RenderFunc(IReadOnlyList<TypedKey> keys, string layoutId);

    private readonly RenderFunc _render;
    public PhraseTracker(RenderFunc render) => _render = render;

    public abstract record WordKind
    {
        private WordKind() { }
        /// <summary>Ambiguity resolved by preference/lock — retro-correctable.</summary>
        public sealed record Defaulted(string Lang) : WordKind;
        /// <summary>Valid in exactly one language — locks the phrase.</summary>
        public sealed record Locked(string Lang) : WordKind;
        /// <summary>Kept / valid as typed — reproduced verbatim in corrections.</summary>
        public sealed record Neutral : WordKind;
    }

    public sealed class PhraseWord
    {
        public required IReadOnlyList<TypedKey> Keys { get; init; }
        public required string ShownText { get; set; } // what this word looks like on screen right now
        public required int SpacesAfter { get; set; }
        public required WordKind Kind { get; set; }
    }

    /// <summary>Maximum characters a correction may erase — bounds worst-case erase chains.</summary>
    public const int MaxCorrectionLength = 200;

    private readonly List<PhraseWord> _words = new();
    public IReadOnlyList<PhraseWord> Words => _words;

    /// <summary>Bumped on every reset; a stale generation drops a record/confirm that lost a race.</summary>
    public int Generation { get; private set; }

    /// <summary>The language the phrase is locked to (first exactly-one-language word), null if none.</summary>
    public string? LockedLang =>
        _words.Select(w => w.Kind).OfType<WordKind.Locked>().Select(l => l.Lang).FirstOrDefault();

    public void Reset()
    {
        _words.Clear();
        Generation++;
    }

    /// <summary>Records an evaluated word. Pass <paramref name="ifGeneration"/> from a deferred caller
    /// so a record that lost the race against a reset is dropped instead of corrupting the phrase.</summary>
    public void Record(IReadOnlyList<TypedKey> keys, string shownText, int spacesAfter,
                       WordKind kind, int? ifGeneration = null)
    {
        if (ifGeneration is int g && g != Generation) return;
        _words.Add(new PhraseWord { Keys = keys, ShownText = shownText, SpacesAfter = spacesAfter, Kind = kind });
    }

    /// <summary>An extra space arrived after the last word (no new word between) — keeps the segment
    /// character math exact for multi-space runs.</summary>
    public void NoteExtraSpace()
    {
        if (_words.Count > 0) _words[^1].SpacesAfter++;
    }

    /// <summary>A planned retro-correction: the on-screen segment to erase, its replacement, the index
    /// it starts at, and the updated word records to store once the replacement succeeded.</summary>
    public sealed record Correction(string OldSegment, string NewSegment, int FirstIndex,
                                    IReadOnlyList<PhraseWord> CorrectedWords);

    /// <summary>
    /// Builds the correction toward <paramref name="lang"/> (rendered through <paramref name="layoutId"/>):
    /// the segment from the first word defaulted to a *different* language through the last recorded
    /// word. Defaulted words re-render their keystrokes; neutral/locked words are reproduced verbatim.
    /// Null when nothing is defaulted to another language, the phrase is locked to a conflicting
    /// language, a re-render fails, or the segment exceeds the length cap.
    /// </summary>
    public Correction? BuildCorrection(string lang, string layoutId)
    {
        if (LockedLang is string locked && locked != lang) return null;

        var first = -1;
        for (var i = 0; i < _words.Count; i++)
            if (_words[i].Kind is WordKind.Defaulted d && d.Lang != lang) { first = i; break; }
        if (first < 0) return null;

        var old = ""; var neo = "";
        var corrected = new List<PhraseWord>();
        for (var index = first; index < _words.Count; index++)
        {
            var w = _words[index];
            var spaces = new string(' ', w.SpacesAfter);
            old += w.ShownText + spaces;

            var shown = w.ShownText;
            var kind = w.Kind;
            if (w.Kind is WordKind.Defaulted dd && dd.Lang != lang)
            {
                var rerendered = _render(w.Keys, layoutId);
                if (rerendered is null) return null;
                shown = rerendered;
                kind = new WordKind.Defaulted(lang);
            }
            neo += shown + spaces;
            corrected.Add(new PhraseWord { Keys = w.Keys, ShownText = shown, SpacesAfter = w.SpacesAfter, Kind = kind });
        }
        if (old.Length > MaxCorrectionLength) return null;
        return new Correction(old, neo, first, corrected);
    }

    /// <summary>Commits a successful correction to the memory (with the generation captured when the
    /// correction was planned).</summary>
    public void Confirm(Correction correction, int ifGeneration)
    {
        if (ifGeneration != Generation) return;
        if (correction.FirstIndex + correction.CorrectedWords.Count != _words.Count)
        {
            Reset(); // the phrase changed shape while the retype ran — memory is unreliable
            return;
        }
        _words.RemoveRange(correction.FirstIndex, _words.Count - correction.FirstIndex);
        _words.AddRange(correction.CorrectedWords);
    }
}

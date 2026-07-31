namespace Switcher3way.Core;

/// <summary>
/// N-way layout detection: renders the typed keys through every installed layout that has a
/// dictionary, validates the word in that layout's language, and switches only when there is
/// exactly one unambiguous target. Precision-first — words valid in more than one language
/// (e.g. <c>там</c> in uk &amp; ru) are left alone. A faithful port of the macOS <c>NWayResolver</c>.
/// </summary>
public sealed class NWayResolver
{
    private readonly ILayoutCatalog _layouts;
    private readonly IDictionaryValidator _dict;
    private readonly IAlwaysConvertList _always;

    public NWayResolver(ILayoutCatalog layouts, IDictionaryValidator dict, IAlwaysConvertList always)
    {
        _layouts = layouts;
        _dict = dict;
        _always = always;
    }

    private sealed record Candidate(string LayoutId, string Lang, string Text, bool IsValid);

    private static string Two(string lang) => lang.Length <= 2 ? lang : lang.Substring(0, 2);

    /// <summary>
    /// Legacy single-winner view of <see cref="Evaluate"/>: the <see cref="Decision"/> only when
    /// exactly one language matches (a <see cref="Outcome.Convert"/>), otherwise null. Ambiguous
    /// (uk↔ru) input collapses to null here — callers wanting the ambiguity use <see cref="Evaluate"/>.
    /// </summary>
    public Decision? Resolve(IReadOnlyList<TypedKey> keys, bool capsLock) =>
        Evaluate(keys, capsLock) is Outcome.Convert c ? c.Decision : null;

    /// <summary>
    /// Full evaluation: render the input through every dictionaried layout and decide.
    /// <see cref="Outcome.Keep"/> when the current layout/language can't be resolved, the word is
    /// already valid in the current language, or no other language matches; <see cref="Outcome.Convert"/>
    /// for exactly one target; <see cref="Outcome.Ambiguous"/> when several match (the caller applies
    /// the preferred-language / phrase-lock policy).
    /// </summary>
    public Outcome Evaluate(IReadOnlyList<TypedKey> keys, bool capsLock)
    {
        if (keys.Count == 0) return new Outcome.Keep();

        var layouts = _layouts.InstalledLayouts();
        var currentId = _layouts.CurrentLayoutId();
        var currentLayout = layouts.FirstOrDefault(l => l.Id == currentId);
        if (currentLayout?.Lang is null) return new Outcome.Keep();
        var currentLang = Two(currentLayout.Lang);

        // One candidate per language (layouts of the same language collapse, preferring the valid
        // render). Validity is judged on the letter core so edge punctuation doesn't hide a word.
        var byLang = new Dictionary<string, Candidate>();
        foreach (var layout in layouts)
        {
            if (layout.Lang is null) continue;
            var lang = Two(layout.Lang);
            if (!_dict.IsAvailable(lang)) continue;
            var rendered = _layouts.Render(keys, layout);
            if (rendered is null) continue;
            var valid = _dict.IsValidWord(SoftGates.LetterCore(rendered).ToLowerInvariant(), lang);
            if (byLang.TryGetValue(lang, out var existing))
            {
                if (valid && !existing.IsValid)
                    byLang[lang] = new Candidate(layout.Id, lang, rendered, true);
            }
            else
            {
                byLang[lang] = new Candidate(layout.Id, lang, rendered, valid);
            }
        }

        if (!byLang.TryGetValue(currentLang, out var current)) return new Outcome.Keep();

        // always-convert — an explicit user override: switch even bypassing the dictionary/vetoes.
        foreach (var cand in byLang.Values)
            if (cand.Lang != currentLang && _always.IsAlwaysConvert(SoftGates.LetterCore(cand.Text)))
                return new Outcome.Convert(new Decision(cand.LayoutId, current.Text, cand.Text));

        // Typed correctly in the current language → do nothing.
        if (current.IsValid) return new Outcome.Keep();

        // Other languages where the input's letter core is a real word. Only the letter core is
        // validated; the whole token is re-rendered in the target on output (punctuation keys convert
        // too — the "," key is "б" on ЙЦУКЕН, etc.).
        var winners = new List<Winner>();
        foreach (var cand in byLang.Values)
        {
            if (cand.Lang == currentLang) continue;
            var core = SoftGates.LetterCore(cand.Text);
            if (!SoftGates.PassesSoftGates(core, capsLock)) continue;
            if (!_dict.IsValidWord(core.ToLowerInvariant(), cand.Lang)) continue;
            winners.Add(new Winner(cand.Lang, cand.LayoutId, cand.Text));
        }

        // 0 — not wrong-layout; 1 — convert; >1 — ambiguous (uk↔ru): caller applies the policy.
        if (winners.Count == 0) return new Outcome.Keep();
        if (winners.Count > 1) return new Outcome.Ambiguous(current.Text, winners);
        return new Outcome.Convert(new Decision(winners[0].LayoutId, current.Text, winners[0].Converted));
    }

    /// <summary>How the keys look in the current layout — the text on screen when nothing converts.</summary>
    public string? RenderCurrent(IReadOnlyList<TypedKey> keys)
    {
        var current = _layouts.InstalledLayouts().FirstOrDefault(l => l.Id == _layouts.CurrentLayoutId());
        return current is null ? null : _layouts.Render(keys, current);
    }

    /// <summary>How the keys look in the layout with <paramref name="layoutId"/> — used by phrase
    /// corrections to re-render defaulted words into the newly established language.</summary>
    public string? Render(IReadOnlyList<TypedKey> keys, string layoutId)
    {
        var layout = _layouts.InstalledLayouts().FirstOrDefault(l => l.Id == layoutId);
        return layout is null ? null : _layouts.Render(keys, layout);
    }

    /// <summary>
    /// Manual-trigger plan: the original render + ordered candidates to cycle through. Unlike
    /// <see cref="Resolve"/>, this is an explicit user action, so it cycles through ALL layouts that
    /// give a different render (even without a dictionary and under ambiguity); the unambiguous
    /// dictionary winner, if any, is placed first. Null if a render is impossible.
    /// </summary>
    public ManualPlan? ManualPlan(IReadOnlyList<TypedKey> keys, bool capsLock,
                                  string? preferredAmbiguityLang = null)
    {
        if (keys.Count == 0) return null;
        // Remote-desktop forwarded chars render identically in every layout — cycling is pointless.
        if (keys.Any(k => k.Char != null)) return null;

        var layouts = _layouts.InstalledLayouts();
        var currentId = _layouts.CurrentLayoutId();
        var currentLayout = layouts.FirstOrDefault(l => l.Id == currentId);
        if (currentLayout is null) return null;
        var original = _layouts.Render(keys, currentLayout);
        if (original is null) return null;

        var ordered = Rotate(layouts, currentId);
        var candidates = new List<ManualCandidate>();
        var seen = new HashSet<string> { original };
        foreach (var layout in ordered)
        {
            if (layout.Id == currentId) continue;
            var rendered = _layouts.Render(keys, layout);
            if (rendered is null || seen.Contains(rendered)) continue;
            seen.Add(rendered);
            candidates.Add(new ManualCandidate(layout.Id, rendered));
        }
        if (candidates.Count == 0) return null;

        // Put the "correct" layout first, so one tap gives it. Unambiguous → the dictionary winner;
        // ambiguous (uk↔ru) → the preferred ambiguity language, so one tap matches auto-fix.
        string? promoteLayoutId = null, promoteConverted = null;
        switch (Evaluate(keys, capsLock))
        {
            case Outcome.Convert c:
                promoteLayoutId = c.Decision.TargetLayoutId;
                promoteConverted = c.Decision.Converted;
                break;
            case Outcome.Ambiguous a when preferredAmbiguityLang is string p && p != "off":
                var w = a.Winners.FirstOrDefault(x => x.Lang == p);
                if (w is not null) { promoteLayoutId = w.LayoutId; promoteConverted = w.Converted; }
                break;
        }
        if (promoteLayoutId is not null)
        {
            var idx = candidates.FindIndex(c => c.TargetLayoutId == promoteLayoutId);
            if (idx < 0) idx = candidates.FindIndex(c => c.Converted == promoteConverted);
            if (idx >= 0)
            {
                var w = candidates[idx];
                candidates.RemoveAt(idx);
                candidates.Insert(0, w);
            }
        }

        return new ManualPlan(original, currentId, candidates);
    }

    /// <summary>The layouts rotated to start right AFTER <paramref name="afterId"/>.</summary>
    private static IReadOnlyList<Layout> Rotate(IReadOnlyList<Layout> layouts, string afterId)
    {
        var i = -1;
        for (var j = 0; j < layouts.Count; j++)
            if (layouts[j].Id == afterId) { i = j; break; }
        if (i < 0) return layouts;

        var res = new List<Layout>(layouts.Count);
        for (var j = i + 1; j < layouts.Count; j++) res.Add(layouts[j]);
        for (var j = 0; j <= i; j++) res.Add(layouts[j]);
        return res;
    }
}

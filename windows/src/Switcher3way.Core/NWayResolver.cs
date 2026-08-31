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

    /// <summary>
    /// The length at which a dictionary hit becomes evidence on its own.
    ///
    /// Below it, two independent things go wrong at once. The hit itself means little: 160 of the 676
    /// two-letter Latin strings are in the English dictionary — <c>ft</c>, <c>bf</c>, <c>kw</c>,
    /// <c>lb</c> — so a short Ukrainian typo has roughly a one-in-four chance of "being an English
    /// word". And the obvious cross-check, asking whether the typed text is a near miss of a word in
    /// the language being typed, stops working too: a word has about (alphabet × 2 × length) one-edit
    /// neighbours, so short words have a near miss almost by definition. Measured against genuine
    /// wrong-layout typing, <see cref="TypoGuard.NearMiss"/> cries wolf on 100% of two-letter words,
    /// 30–40% of four-letter ones, and 0% from six characters up, in both directions.
    ///
    /// So very short words are not decided here at all — they are handed to the phrase around them —
    /// and the near-miss cross-check is only consulted where it still discriminates.
    /// </summary>
    public const int UndecidableBelow = 4;

    /// <summary>
    /// The length from which <see cref="TypoGuard.NearMiss"/> is worth listening to. See
    /// <see cref="UndecidableBelow"/> for why it is useless below this, and note the band between the
    /// two: four and five characters, where the dictionary hit is worth something but the cross-check
    /// is not, so the hit is acted on unless the phrase says otherwise.
    /// </summary>
    public const int NearMissTrustedFrom = 6;

    /// <summary>
    /// The gibberish rescue acts only from this length up. A rescue candidate carries even less
    /// evidence than a short dictionary hit (no dictionary vouches for it at all), but the words
    /// that motivated the feature — <c>апка</c>, <c>айді</c>, <c>Лншм</c> — are four letters, and
    /// below four the shape signals stop meaning anything: almost any 2–3-letter cluster is a
    /// legitimate abbreviation in one of the languages (<c>хз</c>, <c>пн</c>, <c>msg</c>,
    /// <c>pwd</c>). Measured in <c>RescueQualityTests</c> against the checked-in fixture.
    /// </summary>
    public const int RescueFloor = 4;

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
    /// the preferred-language / phrase-lock policy); <see cref="Outcome.Defer"/> when a target matched
    /// but the word is too short for that to mean anything on its own.
    /// </summary>
    /// <param name="phraseLang">
    /// The language the surrounding phrase has already settled into, if any (the caller's
    /// <c>PhraseTracker.LockedLang</c>). It is the tie-breaker for words too short to decide alone:
    /// with it, a two-letter word converts because the phrase says so; without it, the word waits.
    /// </param>
    public Outcome Evaluate(IReadOnlyList<TypedKey> keys, bool capsLock, string? phraseLang = null) =>
        Evaluate(keys, capsLock, phraseLang, weighEvidence: true);

    /// <param name="weighEvidence">
    /// Whether the precision guards apply. They exist to stop the app acting on its own initiative
    /// when the evidence is thin, which is not the situation when the user has pressed the trigger:
    /// an explicit request is entitled to an answer even for a two-letter word, so
    /// <see cref="ManualPlan"/> turns them off.
    /// </param>
    private Outcome Evaluate(IReadOnlyList<TypedKey> keys, bool capsLock, string? phraseLang,
                             bool weighEvidence)
    {
        if (keys.Count == 0) return new Outcome.Keep();

        var layouts = _layouts.InstalledLayouts();
        var currentId = _layouts.CurrentLayoutId();
        var currentLayout = layouts.FirstOrDefault(l => l.Id == currentId);
        if (currentLayout?.Lang is null) return new Outcome.Keep(KeepReason.NoCurrentLanguage);
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

        if (!byLang.TryGetValue(currentLang, out var current)) return new Outcome.Keep(KeepReason.NoCurrentLanguage);

        // always-convert — an explicit user override: switch even bypassing the dictionary/vetoes.
        foreach (var cand in byLang.Values)
            if (cand.Lang != currentLang && _always.IsAlwaysConvert(SoftGates.LetterCore(cand.Text)))
                return new Outcome.Convert(new Decision(cand.LayoutId, current.Text, cand.Text));

        // Typed correctly in the current language → do nothing. Say so: a real word of the language
        // being typed in is the best evidence there is about what language this phrase is.
        if (current.IsValid) return new Outcome.Keep(KeepReason.ValidInCurrent);

        // Other languages where the input's letter core is a real word. Only the letter core is
        // validated; the whole token is re-rendered in the target on output (punctuation keys convert
        // too — the "," key is "б" on ЙЦУКЕН, etc.).
        var winners = new List<Winner>();
        foreach (var cand in byLang.Values)
        {
            if (cand.Lang == currentLang) continue;
            var core = SoftGates.LetterCore(cand.Text);
            if (!SoftGates.PassesSoftGates(core, capsLock)) continue;
            // One verdict per word per decision: the candidate already carries the dictionary's
            // answer. Re-querying here is what let the macOS spellchecker's flip-flop episodes
            // split a single evaluation against itself; Hunspell is deterministic, so on this
            // side it is parity and one query saved.
            if (!cand.IsValid) continue;
            winners.Add(new Winner(cand.Lang, cand.LayoutId, cand.Text));
        }

        // 0 — not wrong-layout; 1 — convert; >1 — ambiguous (uk↔ru): caller applies the policy.
        // Last resort before keeping: jargon, loanwords and names validate NOWHERE, so a dictionary
        // can never rescue them — but a word typed in the wrong layout is gibberish in the layout it
        // landed in and word-shaped in the one it was meant for, and that asymmetry is checkable.
        if (winners.Count == 0) return Rescue(current, byLang, capsLock) ?? new Outcome.Keep();

        // Both guards below weigh how much the dictionary hit is actually worth, and the order between
        // them matters: the near-miss test is itself meaningless on a very short word, because almost
        // any two-letter string is one edit from one of the 160 the English dictionary accepts. Short
        // words are settled by the phrase; only longer ones are worth second-guessing as typos.
        // How far the dictionary hit can be trusted depends almost entirely on how long the word is,
        // and the two guards below cover different bands of that. Long words are checked against the
        // likelier story — that a key was missed in the language already being typed. Short words
        // cannot be checked that way at all, because at that length every string has a near miss, so
        // they are settled by the phrase around them instead.
        var coreLength = SoftGates.LetterCore(current.Text).Length;
        if (weighEvidence && coreLength < NearMissTrustedFrom)
        {
            // Short enough that the near-miss cross-check below would fire on anything, so the phrase
            // arbitrates instead. Agreeing with the language already being written is corroboration;
            // contradicting it is not enough to overturn it.
            var byPhrase = phraseLang is null ? null : winners.FirstOrDefault(w => w.Lang == phraseLang);
            if (byPhrase is not null)
                return _dict.VerifyTrust(byPhrase.Lang)
                    ? new Outcome.Convert(new Decision(byPhrase.LayoutId, current.Text, byPhrase.Converted))
                    : new Outcome.Keep(KeepReason.DictionaryUntrusted);
            if (phraseLang is not null) return new Outcome.Keep(KeepReason.PhraseDisagrees);

            // Nothing has settled the phrase yet. Under four characters there is no honest way to tell
            // a short Ukrainian word from a short English one, so hold the word — unconverted, but
            // with its keystrokes remembered, so the word that does settle the phrase converts this
            // one along with it. That is what stops the caution from being a plain loss of recall.
            if (coreLength < UndecidableBelow) return new Outcome.Defer(current.Text, winners);
            // Four or five characters, with nothing to contradict it: worth acting on.
        }

        // Before accepting "this is a word in another language",
        // check the likelier story: that it is a word of *this* language with one key missed. A
        // fumbled key is a simpler explanation than a keyboard that changed for one word and changed
        // back, and this is the check the resolver never had.
        if (weighEvidence &&
            TypoGuard.NearMiss(SoftGates.LetterCore(current.Text).ToLowerInvariant(), currentLang, _dict))
            return new Outcome.Keep(KeepReason.LooksLikeATypo);

        // About to act on a dictionary verdict. Confirm the dictionary is still answering
        // correctly: an episode that began after the last periodic check would otherwise convert a
        // name into keyboard mash and take the layout with it. No-op where the validator cannot
        // verify itself, which is the Hunspell case.
        var trusted = winners.Where(w => _dict.VerifyTrust(w.Lang)).ToList();
        if (trusted.Count == 0) return new Outcome.Keep(KeepReason.DictionaryUntrusted);
        if (trusted.Count > 1) return new Outcome.Ambiguous(current.Text, trusted);
        return new Outcome.Convert(new Decision(trusted[0].LayoutId, current.Text, trusted[0].Converted));
    }

    /// <summary>
    /// The gibberish rescue: no dictionary validates the word in any language, so the shape of the
    /// renderings is the only evidence left. Convert only when the typed side is gibberish AND a
    /// candidate side is word-shaped — one-sided implausibility is not enough (<c>npm</c> is
    /// gibberish in English, but so is its Cyrillic rendering, so it keeps). Null when the rescue
    /// does not apply; the caller then keeps as before. A port of the macOS <c>rescue</c>,
    /// deliberately branch-for-branch comparable with it.
    /// </summary>
    private Outcome? Rescue(Candidate current, Dictionary<string, Candidate> byLang, bool capsLock)
    {
        // The dictionary path's own vetoes first, on the UN-lowercased core: the all-caps and
        // camelCase vetoes are about letter case, and lowercasing first would blind them.
        var rawCore = SoftGates.LetterCore(current.Text);
        if (!SoftGates.PassesSoftGates(rawCore, capsLock)) return null;
        var core = rawCore.ToLowerInvariant();
        if (core.Length < RescueFloor) return null;

        // Shape of the typed side. An empty vowel set means this language's shape is unknown —
        // then nothing can be called gibberish and the rescue stays out of the way (fail-open,
        // like the near-miss alphabet).
        var currentVowels = _dict.Vowels(current.Lang);
        if (currentVowels.Length == 0) return null;
        if (WordShape.IsPlausible(core, currentVowels, current.Lang)) return null;

        // Not a typo either: if the typed language holds a word one keystroke away, a fumbled key
        // stays the simpler story, exactly as on the dictionary path — and it is reported as that
        // story, not as a generic keep.
        if (TypoGuard.NearMiss(core, current.Lang, _dict)) return new Outcome.Keep(KeepReason.LooksLikeATypo);

        // The candidates that ARE word-shaped in their own language.
        var plausible = new List<Winner>();
        foreach (var cand in byLang.Values)
        {
            if (cand.Lang == current.Lang) continue;
            var candVowels = _dict.Vowels(cand.Lang);
            if (candVowels.Length == 0) continue;
            var candCore = SoftGates.LetterCore(cand.Text).ToLowerInvariant();
            if (!WordShape.IsPlausible(candCore, candVowels, cand.Lang)) continue;
            plausible.Add(new Winner(cand.Lang, cand.LayoutId, cand.Text));
        }

        switch (plausible.Count)
        {
            case 0:
                return null;
            case 1:
                return new Outcome.Rescued(new Decision(plausible[0].LayoutId, current.Text, plausible[0].Converted));
            default:
                // The uk/ru pair is the ambiguity the preference setting exists for; report it the
                // same way dictionary words shared by both languages are reported. Anything wider —
                // plausible across scripts — is a coin toss, and a wrong pick costs the user the
                // sentence while a keep costs one trigger tap.
                var langs = plausible.Select(w => w.Lang).ToHashSet();
                if (langs.SetEquals(new[] { "ru", "uk" })) return new Outcome.Ambiguous(current.Text, plausible);
                return null;
        }
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
        switch (Evaluate(keys, capsLock, phraseLang: null, weighEvidence: false))
        {
            case Outcome.Convert c:
                promoteLayoutId = c.Decision.TargetLayoutId;
                promoteConverted = c.Decision.Converted;
                break;
            case Outcome.Rescued r:
                promoteLayoutId = r.Decision.TargetLayoutId;
                promoteConverted = r.Decision.Converted;
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

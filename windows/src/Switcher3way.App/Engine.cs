using System.Collections.Concurrent;
using Switcher3way.Core;
using Switcher3way.Dictionaries;

namespace Switcher3way.App;

/// <summary>A successful conversion, for the on-screen feedback (caret chip / toast).</summary>
internal sealed record ConversionInfo(string Original, string Converted, string Lang);

/// <summary>Empty override list (used by the self-test).</summary>
internal sealed class EmptyAlwaysConvert : IAlwaysConvertList
{
    public bool IsAlwaysConvert(string converted) => false;
}

/// <summary>Always-convert list backed by user settings.</summary>
internal sealed class SettingsAlwaysConvert : IAlwaysConvertList
{
    private readonly SettingsManager _s;
    public SettingsAlwaysConvert(SettingsManager s) => _s = s;
    public bool IsAlwaysConvert(string converted) => _s.IsAlwaysConvertWord(converted);
}

/// <summary>
/// Wires the keyboard monitor to the tested Core (<see cref="NWayResolver"/> + real Hunspell) and
/// the Win32 switch/rewrite. Detection decisions come from Core; this class only marshals work off
/// the hook thread and drives the manual N-way cycle. Auto path and manual cycle both run on the
/// worker thread (SendInput + sleeps must not block the hook).
/// </summary>
internal sealed class Engine
{
    private readonly Win32LayoutCatalog _catalog = new();
    private readonly IDictionaryValidator _dict = new HunspellDictionaryValidator();
    private readonly NWayResolver _resolver;
    private readonly PhraseTracker _phrase;
    private readonly KeyboardMonitor _monitor;
    private readonly BlockingCollection<Action> _work = new();

    private volatile bool _converting;
    private readonly object _cycleLock = new();
    private Cycle? _cycle;

    /// <summary>User-facing notification (e.g. "can't act in this window"), shown by the tray.</summary>
    public event Action<string>? Notify;
    private DateTime _lastNotify = DateTime.MinValue;

    /// <summary>A conversion that reached the screen: what was typed, what replaced it, target language.</summary>
    public event Action<ConversionInfo>? Converted;
    private void RaiseConverted(string original, string converted, string layoutId) =>
        Converted?.Invoke(new ConversionInfo(original.TrimEnd(), converted.TrimEnd(), LangOf(layoutId)));

    /// <summary>
    /// A conversion the user undid: the text and layout are back to what they typed. Carries the
    /// original and the converted form so the UI can offer to leave that word alone in future.
    /// </summary>
    public event Action<string, string>? Undone;

    private void NotifyProtected()
    {
        var now = DateTime.Now;
        if ((now - _lastNotify).TotalSeconds < 30) return; // throttle so an elevated window can't spam
        _lastNotify = now;
        Notify?.Invoke(Loc.T("notify.protected"));
    }

    private sealed class Cycle
    {
        public required ManualPlan Plan;
        public required string Suffix;   // trailing boundary char to preserve (" " if word was finished)
        public int Step;                 // 0..Candidates.Count; == Count → restore original
        public int OnScreenLen;          // chars currently displayed for the token
        /// <summary>Started from a selection: the first replacement erases it with one backspace.</summary>
        public bool FromSelection;
    }

    private readonly SettingsManager _settings;

    // Per-app layout memory: last-used layout per exe, and the app we're currently tracking.
    private readonly Dictionary<string, IntPtr> _appLayouts = new(StringComparer.OrdinalIgnoreCase);
    private string? _lastExe;
    private uint _lastThread;

    public Engine(SettingsManager settings)
    {
        _settings = settings;
        Diagnostics.Configure(settings);
        _monitor = new KeyboardMonitor(settings);
        _resolver = new NWayResolver(_catalog, _dict, new SettingsAlwaysConvert(settings));
        _phrase = new PhraseTracker((keys, layoutId) => _resolver.Render(keys, layoutId));
        _monitor.WordCompleted += (word, boundary) =>
        {
            // Auto-fix gates on the master toggle, not-paused, AND the auto-fix setting.
            if (_settings.EffectivelyEnabled && _settings.AutoFix)
                _work.Add(() => AutoConvert(word, boundary));
        };
        _monitor.TriggerPressed += OnTrigger;
        _monitor.Typed += () => { lock (_cycleLock) _cycle = null; };
        _monitor.ForegroundChanged += hwnd => _work.Add(() => OnForegroundChanged(hwnd));
        // Phrase resets/extra-spaces are marshaled onto the worker so all tracker mutation is single-threaded.
        _monitor.PhraseReset += () => _work.Add(() => _phrase.Reset());
        _monitor.ExtraSpace += () => _work.Add(() => _phrase.NoteExtraSpace());
    }

    // ---- Per-app layout memory -------------------------------------------------------------
    private void OnForegroundChanged(IntPtr hwnd)
    {
        uint newThread = Native.GetWindowThreadProcessId(hwnd, out uint pid);
        string newExe = LayoutSwitcher.ExeName(pid);

        // Remember the layout of the app we're leaving.
        if (_lastThread != 0 && _lastExe is not null)
            _appLayouts[_lastExe] = Native.GetKeyboardLayout(_lastThread);

        // Restore the new app's remembered layout (if enabled and different from current).
        if (_settings.EffectivelyEnabled && _settings.PerAppMemory
            && _appLayouts.TryGetValue(newExe, out var hkl) && hkl != IntPtr.Zero
            && Native.GetKeyboardLayout(newThread) != hkl)
        {
            LayoutSwitcher.SwitchForeground(Win32LayoutCatalog.HklToId(hkl));
        }

        _lastExe = newExe;
        _lastThread = newThread;
    }

    /// <summary>Start the keyboard/mouse hook + conversion worker (both background). Non-blocking.</summary>
    public void Start()
    {
        var hookThread = new Thread(_monitor.Run) { IsBackground = true, Name = "hook" };
        hookThread.SetApartmentState(ApartmentState.STA);
        hookThread.Start();
        new Thread(WorkerLoop) { IsBackground = true, Name = "worker" }.Start();
    }

    public void Stop() => _work.CompleteAdding();

    private void WorkerLoop()
    {
        foreach (var job in _work.GetConsumingEnumerable())
        {
            try { job(); }
            catch (Exception ex) { Diagnostics.Log($"  [error] {ex.Message}"); }
        }
    }

    // ---- Auto path (phrase-aware) ----------------------------------------------------------
    private void AutoConvert(IReadOnlyList<TypedKey> word, char boundary)
    {
        if (_settings.IsDeniedApp(LayoutSwitcher.Foreground().Exe)) { _phrase.Reset(); return; } // terminals / RDP / pw
        if (SecureField.IsFocusedPassword())                                 // never touch a password field
        { Diagnostics.Log("  auto: suppressed — password field"); _phrase.Reset(); return; }

        bool caps = word.Any(k => k.Caps);
        var outcome = _resolver.Evaluate(word, caps);
        int gen = _phrase.Generation;
        bool hardBoundary = boundary != ' '; // Enter/Tab ends the phrase after this word

        switch (outcome)
        {
            case Outcome.Keep:
                _phrase.Record(word, _resolver.RenderCurrent(word) ?? "", 1, new PhraseTracker.WordKind.Neutral(), gen);
                break;

            case Outcome.Convert conv:
            {
                var d = conv.Decision;
                if (_settings.IsNeverConvert(d.Original, d.Converted))
                {
                    _phrase.Record(word, d.Original, 1, new PhraseTracker.WordKind.Neutral(), gen);
                    break;
                }
                var lang = LangOf(d.TargetLayoutId);
                // A single-winner word locks the phrase. If earlier words were defaulted to a
                // different language (and no conflicting lock), re-convert the whole segment as one.
                var corr = _phrase.BuildCorrection(lang, d.TargetLayoutId);
                if (corr is not null && corr.OldSegment.Length + d.Original.Length + 1 <= PhraseTracker.MaxCorrectionLength)
                    ApplyCorrection(word, d, corr, boundary, lang, gen);
                else
                    ConvertSingle(word, d, boundary, new PhraseTracker.WordKind.Locked(lang), gen);
                break;
            }

            case Outcome.Ambiguous amb:
            {
                // Prefer the phrase lock, else the setting. "off" or no matching winner → keep.
                var target = _phrase.LockedLang ?? (_settings.AmbiguousLang == "off" ? null : _settings.AmbiguousLang);
                var w = target is null ? null : amb.Winners.FirstOrDefault(x => x.Lang == target);
                if (w is null || _settings.IsNeverConvert(amb.Original, w.Converted))
                {
                    _phrase.Record(word, amb.Original, 1, new PhraseTracker.WordKind.Neutral(), gen);
                    break;
                }
                ConvertSingle(word, new Decision(w.LayoutId, amb.Original, w.Converted), boundary,
                              new PhraseTracker.WordKind.Defaulted(w.Lang), gen);
                break;
            }
        }

        if (hardBoundary) _phrase.Reset();
    }

    /// <summary>Convert one word: rewrite while still in the source layout, switch only on success
    /// (so an aborted/failed conversion leaves the layout the user was typing in), then record it.</summary>
    private void ConvertSingle(IReadOnlyList<TypedKey> word, Decision d, char boundary,
                               PhraseTracker.WordKind kind, int gen)
    {
        // Same text in the target layout (Cyrillic identical across uk/ru): switch only, no rewrite.
        if (d.Converted == d.Original)
        {
            var swPath = LayoutSwitcher.SwitchForeground(d.TargetLayoutId);
            Diagnostics.Log($"  auto: layout -> [{LangLabel(d.TargetLayoutId)}] (text \"{d.Original}\" unchanged) via {swPath}");
            _phrase.Record(word, d.Converted, 1, kind, gen);
            return;
        }
        // The boundary char is already on screen; erase word+boundary, re-type converted+boundary.
        var res = ArmedRewrite(word.Count + 1, d.Converted + boundary, d.Original + boundary);
        if (res == TextRewriter.Result.Ok)
        {
            var prevLayout = _catalog.CurrentLayoutId(); // before the switch — the cancel target
            var path = LayoutSwitcher.SwitchForeground(d.TargetLayoutId);
            Diagnostics.Log($"  auto: \"{d.Original}\" -> \"{d.Converted}\" [{LangLabel(d.TargetLayoutId)}] via {path} : {res}");
            _phrase.Record(word, d.Converted, 1, kind, gen);
            RaiseConverted(d.Original, d.Converted, d.TargetLayoutId);
            SeedCancelCycle(d.Original, d.Converted, boundary, d.TargetLayoutId, prevLayout);
        }
        else if (res == TextRewriter.Result.Aborted)
        {
            Diagnostics.Log($"  auto: \"{d.Original}\" -> aborted (user typed)");
            _phrase.Reset(); // screen state uncertain — drop phrase memory
        }
        else { Diagnostics.Log($"  auto: \"{d.Original}\" -> \"{d.Converted}\" : {res}"); NotifyProtected(); }
    }

    /// <summary>Apply a phrase correction + the current word as one segment rewrite, then switch.</summary>
    private void ApplyCorrection(IReadOnlyList<TypedKey> word, Decision d, PhraseTracker.Correction corr,
                                 char boundary, string lang, int gen)
    {
        var oldSeg = corr.OldSegment + d.Original + boundary;
        var newSeg = corr.NewSegment + d.Converted + boundary;
        var res = ArmedRewrite(oldSeg.Length, newSeg, oldSeg);
        if (res == TextRewriter.Result.Ok)
        {
            var prevLayout = _catalog.CurrentLayoutId(); // before the switch — the cancel target
            var path = LayoutSwitcher.SwitchForeground(d.TargetLayoutId);
            Diagnostics.Log($"  auto: phrase -> [{LangLabel(d.TargetLayoutId)}] \"{newSeg.TrimEnd()}\" via {path} : {res}");
            _phrase.Confirm(corr, gen);
            _phrase.Record(word, d.Converted, 1, new PhraseTracker.WordKind.Locked(lang), gen);
            RaiseConverted(d.Original, d.Converted, d.TargetLayoutId);
            // One trigger tap cancels the whole segment, not just the last word.
            SeedCancelCycle(corr.OldSegment + d.Original, corr.NewSegment + d.Converted, boundary,
                            d.TargetLayoutId, prevLayout);
        }
        else if (res == TextRewriter.Result.Aborted)
        {
            Diagnostics.Log("  auto: phrase correction aborted (user typed)");
            _phrase.Reset();
        }
        else { Diagnostics.Log($"  auto: phrase correction : {res}"); NotifyProtected(); }
    }

    /// <summary>A rewrite guarded by the abort flag: a real keystroke mid-stream aborts and restores.</summary>
    private TextRewriter.Result ArmedRewrite(int eraseCount, string replacement, string original)
    {
        _monitor.ArmRewrite();
        try
        {
            return TextRewriter.Rewrite(eraseCount, replacement, original: original,
                                        shouldAbort: () => _monitor.RewriteAborted);
        }
        finally { _monitor.DisarmRewrite(); }
    }

    /// <summary>Friendly language label (en/ru/uk) for a layout id, for logging.</summary>
    private string LangLabel(string layoutId) =>
        _catalog.InstalledLayouts().FirstOrDefault(l => l.Id == layoutId)?.Lang ?? layoutId;

    /// <summary>The 2-letter language of a layout id (defaults to the id if unknown).</summary>
    private string LangOf(string layoutId)
    {
        var lang = _catalog.InstalledLayouts().FirstOrDefault(l => l.Id == layoutId)?.Lang;
        return lang is null ? layoutId : (lang.Length <= 2 ? lang : lang.Substring(0, 2));
    }

    /// <summary>
    /// Seed the trigger cycle from an applied auto-fix: the converted text is the only candidate
    /// and it is already on screen (Step = 1), so the next trigger press — with no typing in
    /// between — restores the original text and the pre-conversion layout: the one-tap cancel
    /// the macOS app has. Real typing clears the cycle via the monitor's Typed event.
    /// </summary>
    private void SeedCancelCycle(string original, string converted, char boundary,
                                 string targetLayoutId, string previousLayoutId)
    {
        var plan = new ManualPlan(original, previousLayoutId,
                                  new[] { new ManualCandidate(targetLayoutId, converted) });
        lock (_cycleLock)
            _cycle = new Cycle { Plan = plan, Suffix = boundary.ToString(), Step = 1,
                                 OnScreenLen = converted.Length + 1 };
    }

    // ---- Manual N-way cycle ----------------------------------------------------------------
    private void OnTrigger()
    {
        if (!_settings.EffectivelyEnabled) return; // manual works when enabled + not paused (even if auto-fix off)
        if (_converting) return;   // ignore F9 auto-repeat / re-entrancy
        _converting = true;
        _work.Add(() => { try { ManualStep(); } finally { _converting = false; } });
    }

    /// <summary>
    /// Begin a manual cycle: from the recorded keystrokes when we have them, otherwise from the
    /// current selection (selecting with the mouse or Shift+arrows clears the buffer, so the
    /// selection path is what makes "convert what I highlighted" work). Null — nothing to convert.
    /// </summary>
    private Cycle? StartCycle()
    {
        var (cur, prev) = _monitor.Snapshot();
        if (cur.Count > 0 || prev.Count > 0)
        {
            var word = cur.Count > 0 ? cur : prev;
            var suffix = cur.Count > 0 ? "" : " ";       // finished word: the boundary space is on screen
            var plan = _resolver.ManualPlan(word, word.Any(k => k.Caps), _settings.AmbiguousLang);
            if (plan is null) { Diagnostics.Log("(nothing to convert)"); return null; }
            return new Cycle { Plan = plan, Suffix = suffix, Step = 0, OnScreenLen = (plan.Original + suffix).Length };
        }

        var selected = Selection.Read();
        if (selected is null)
        {
            Diagnostics.Log($"(type a word or select text, then press {_settings.TriggerLabel})");
            return null;
        }
        if (selected.Length > Selection.MaxChars)
        {
            Diagnostics.Log($"  selection: {selected.Length} chars — too long, skipped");
            return null;
        }
        var selPlan = SelectionPlan(selected);
        if (selPlan is null) { Diagnostics.Log($"  selection: \"{selected}\" — no other layout renders it differently"); return null; }
        Diagnostics.Log($"  selection: \"{selected}\" → {selPlan.Candidates.Count} candidate(s)");
        return new Cycle { Plan = selPlan, Suffix = "", Step = 0, OnScreenLen = selected.Length, FromSelection = true };
    }

    /// <summary>
    /// Build a manual plan from on-screen text: map each character back to the keystroke that
    /// produced it (in whichever installed layout can represent the whole string), then render those
    /// keystrokes through the other layouts. A dictionary-valid candidate is offered first, preferring
    /// the ambiguity language, so one tap gives the expected result.
    /// </summary>
    private ManualPlan? SelectionPlan(string text)
    {
        var layouts = _catalog.InstalledLayouts();
        var currentId = _catalog.CurrentLayoutId();

        // Source layout: the active one if it can type this text, else any layout that can.
        var ordered = layouts.OrderByDescending(l => l.Id == currentId);
        Layout? source = null;
        List<TypedKey>? keys = null;
        foreach (var l in ordered)
        {
            var map = _catalog.ReverseMap(l);
            var mapped = new List<TypedKey>(text.Length);
            bool ok = true;
            foreach (var ch in text)
            {
                if (map.TryGetValue(ch, out var k)) mapped.Add(k);
                else { ok = false; break; }
            }
            if (ok) { source = l; keys = mapped; break; }
        }
        if (source is null || keys is null) return null;

        var candidates = new List<ManualCandidate>();
        var seen = new HashSet<string> { text };
        foreach (var l in layouts)
        {
            if (l.Id == source.Id) continue;
            var rendered = _catalog.Render(keys, l);
            if (rendered is null || !seen.Add(rendered)) continue;
            candidates.Add(new ManualCandidate(l.Id, rendered));
        }
        if (candidates.Count == 0) return null;

        // Promote a dictionary-valid candidate (preferring the ambiguity language).
        var valid = candidates.Where(c =>
        {
            var lang = LangOf(c.TargetLayoutId);
            var core = SoftGates.LetterCore(c.Converted).ToLowerInvariant();
            return core.Length > 0 && _dict.IsAvailable(lang) && _dict.IsValidWord(core, lang);
        }).ToList();
        var pick = valid.FirstOrDefault(c => LangOf(c.TargetLayoutId) == _settings.AmbiguousLang) ?? valid.FirstOrDefault();
        if (pick is not null)
        {
            candidates.Remove(pick);
            candidates.Insert(0, pick);
        }
        return new ManualPlan(text, source.Id, candidates);
    }

    private void ManualStep()
    {
        if (_settings.IsDeniedApp(LayoutSwitcher.Foreground().Exe)) return; // safety: never touch text here
        if (SecureField.IsFocusedPassword())                                // never touch a password field
        { Diagnostics.Log("  manual: suppressed — password field"); return; }
        Cycle? cyc;
        lock (_cycleLock) cyc = _cycle;
        if (cyc is null)
        {
            cyc = StartCycle();                       // may read the selection (no lock held: it blocks)
            if (cyc is null) return;
            lock (_cycleLock) _cycle = cyc;
        }

        // Manual control invalidates the phrase memory: its rewrites aren't tracked, so a later
        // phrase correction would be computed over text that is no longer on screen (macOS parity).
        _phrase.Reset();

        bool restore = cyc.Step >= cyc.Plan.Candidates.Count;
        string targetId = restore ? cyc.Plan.OriginalLayoutId : cyc.Plan.Candidates[cyc.Step].TargetLayoutId;
        string label = restore ? $"original:{LangLabel(cyc.Plan.OriginalLayoutId)}" : LangLabel(targetId);
        string text = (restore ? cyc.Plan.Original : cyc.Plan.Candidates[cyc.Step].Converted) + cyc.Suffix;

        var path = LayoutSwitcher.SwitchForeground(targetId);
        // A live selection is erased by a single backspace; afterwards we erase what we typed.
        int erase = cyc.FromSelection && cyc.Step == 0 ? 1 : cyc.OnScreenLen;
        var res = TextRewriter.Rewrite(erase, text, waitForKeyUpVk: _settings.TriggerKey);
        Diagnostics.Log($"  cycle[{cyc.Step}] -> [{label}] \"{text.TrimEnd()}\" via {path} : {res}");
        if (res != TextRewriter.Result.Ok) NotifyProtected();
        // Feedback on manual conversions too, but not on the final restore-to-original step.
        else if (!restore) RaiseConverted(cyc.Plan.Original, text, targetId);
        // The restore step is the user rejecting a conversion — the moment to offer to remember it.
        // The first candidate is what had been on screen, so that is the word to suppress.
        else if (cyc.Plan.Candidates.Count > 0)
            Undone?.Invoke(cyc.Plan.Original.TrimEnd(), cyc.Plan.Candidates[0].Converted.TrimEnd());

        cyc.OnScreenLen = text.Length;
        cyc.Step++;
        if (restore) lock (_cycleLock) _cycle = null; // full loop done; next F9 starts fresh
    }
}

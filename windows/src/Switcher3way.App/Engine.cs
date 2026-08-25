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

    /// <summary>
    /// A run of consecutive short words that were all held (see <see cref="Outcome.Defer"/>) and all
    /// read as the same other language. No single one of them is evidence of anything. Several in a
    /// row are: words only pile up here while nothing in the phrase validates in the layout being
    /// typed in, which is precisely what typing in the wrong layout looks like. Two is enough, and
    /// without this a short message — "як ти?" — would never be fixed at all, because no word in it is
    /// long enough to settle the phrase by itself.
    /// </summary>
    private string? _heldLang;
    private int _heldRun;
    /// <summary>The language a run of held words settled on, standing in for a phrase lock.</summary>
    private string? _settledLang;

    private const int HeldRunSettles = 2;

    private void ForgetHeldRun() { _heldLang = null; _heldRun = 0; _settledLang = null; }

    /// <summary>Drop the phrase and everything derived from it. The held run is part of the phrase's
    /// state, so the two must never be reset apart.</summary>
    private void ResetPhrase() { _phrase.Reset(); ForgetHeldRun(); }
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

    /// <summary>
    /// The manual trigger was pressed but there was nothing to do, with the reason. Every one of these
    /// paths used to return in silence, writing a line to a log that is off by default — so tapping the
    /// trigger on a machine with one keyboard layout, or before typing anything, looked exactly like a
    /// broken app. Store certification failed on precisely that: "no response after a double tap of Ctrl".
    ///
    /// Carries three strings: notification title, notification body, and a short line for the on-screen
    /// chip. Two surfaces, because a notification alone can be suppressed by things the app does not
    /// control (Do Not Disturb, notifications switched off) — and certification reads suppressed as broken.
    /// </summary>
    public event Action<string, string, string>? Hint;

    private DateTime _lastHint = DateTime.MinValue;

    private void RaiseHint(string titleKey, string bodyKey, string chipKey, params object[] args)
    {
        var now = DateTime.Now;
        if ((now - _lastHint).TotalSeconds < 8) return;   // a repeated tap must not stack notifications
        _lastHint = now;
        Hint?.Invoke(Loc.T(titleKey), Loc.Tf(bodyKey, args), Loc.Tf(chipKey, args));
    }

    /// <summary>
    /// Layouts we could actually convert between: a known language with a bundled dictionary. Below two,
    /// the app has nothing to do and should say so rather than appear inert.
    /// </summary>
    private int UsableLayoutCount() =>
        _catalog.InstalledLayouts().Count(l => l.Lang is not null && _dict.IsAvailable(l.Lang));

    /// <summary>
    /// Tell the user a conversion did not happen, in terms of what actually went wrong.
    ///
    /// Every failure used to be reported as "this window may be running as administrator", which is
    /// true for exactly one of them. A conversion refused because the replacement did not land in a
    /// perfectly ordinary window told the user to go and check elevation they do not have, and left
    /// the real behaviour — the app checked its own work, disliked the result, and put the original
    /// back — completely invisible. A message that contradicts what happened is worse than a vague
    /// one, and this app has already had to fix two of them.
    /// </summary>
    private void NotifyFailure(TextRewriter.Result result)
    {
        var now = DateTime.Now;
        if ((now - _lastNotify).TotalSeconds < 30) return; // throttle so one bad window can't spam
        _lastNotify = now;
        Notify?.Invoke(Loc.T(result switch
        {
            // The one case that really is about privilege: Windows refuses synthesized input from a
            // lower integrity level.
            TextRewriter.Result.Protected => "notify.protected",
            // The replacement was checked and did not match, so the original was restored. Nothing was
            // lost, and saying so is the point — otherwise the app looks broken rather than careful.
            TextRewriter.Result.Mismatch => "notify.mismatch",
            // Injection stopped part-way through for a reason other than the user typing.
            TextRewriter.Result.Partial => "notify.partial",
            _ => "notify.protected",
        }));
    }

    private sealed class Cycle
    {
        public required ManualPlan Plan;
        public required string Suffix;   // trailing boundary char to preserve (" " if word was finished)
        public int Step;                 // 0..Candidates.Count; == Count → restore original
        public int OnScreenLen;          // chars currently displayed for the token
        /// <summary>
        /// What is currently displayed for the token. Needed so a step that lands wrong can be put back:
        /// without it the rewriter can only erase what it typed and leave nothing behind.
        /// </summary>
        public required string OnScreenText;
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
        _monitor.PhraseReset += () => _work.Add(ResetPhrase);
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
        if (_settings.IsDeniedApp(LayoutSwitcher.Foreground().Exe)) { ResetPhrase(); return; } // terminals / RDP / pw
        // Log what the guard saw, not just when it fires: "no suppression" is indistinguishable from
        // "guard broken" otherwise, which is exactly how the browser case hid for four releases.
        if (_settings.DebugLog) Diagnostics.Log("  secure: " + SecureField.Describe());
        if (SecureField.IsFocusedPassword())                                 // never touch a password field
        { Diagnostics.Log("  auto: suppressed — password field"); ResetPhrase(); return; }

        bool caps = word.Any(k => k.Caps);
        // The phrase's language goes in, because words too short to decide alone are decided by it.
        var outcome = _resolver.Evaluate(word, caps, _phrase.LockedLang ?? _settledLang);
        int gen = _phrase.Generation;
        bool hardBoundary = boundary != ' '; // Enter/Tab ends the phrase after this word

        // A word finished with Enter or Tab cannot be rewritten, and trying is worse than declining.
        // The rewrite erases the word *and its boundary*, then re-types both — and it types every
        // character as a Unicode code point, which is fine for a space and useless for these: a
        // Windows edit control ignores U+000A and U+000D alike, so the replacement always lands one
        // character short and the read-back correctly refuses it. Measured in Notepad: erase 7, type
        // 7, six arrive, `caret 7 -> 6, expected 7`, repaired back.
        //
        // Re-emitting the boundary as a key press instead would fix a text editor and break a chat
        // box, where Enter already sent the message and pressing it again would send another. There
        // is no way to tell those apart before acting, so the app does not act. The user sees no
        // conversion either way; what they no longer see is a rewrite that runs, fails, undoes itself
        // and raises a notification, every single time they finish a line.
        if (hardBoundary && outcome is Outcome.Convert or Outcome.Ambiguous)
        {
            Diagnostics.Log($"  auto: \"{_resolver.RenderCurrent(word) ?? ""}\" not converted — the word ends "
                            + (boundary == '	' ? "with Tab" : "with Enter")
                            + ", whose boundary character cannot be re-typed");
            ResetPhrase();
            return;
        }

        switch (outcome)
        {
            case Outcome.Keep keep:
            {
                ForgetHeldRun();
                var kept = _resolver.RenderCurrent(word) ?? "";
                // Say so. Leaving a word alone is the app's most common decision and its least visible
                // one: nothing moves on screen either way, so without this line a guard that is working
                // and a guard that never ran produce identical evidence. That ambiguity has already
                // cost this project one round of "it does nothing" that turned out to be correct
                // behaviour, and it is what makes the typo guard unverifiable by hand.
                Diagnostics.Log($"  auto: \"{kept}\" kept — {Explain(keep.Reason)}");
                // A word already valid in the layout it was typed in settles what language this phrase
                // is; nothing else the app sees is stronger. This used to be filed as Neutral, which
                // threw the evidence away and left short words undecidable.
                _phrase.Record(word, kept, 1,
                               keep.ValidInCurrent
                                   ? new PhraseTracker.WordKind.Locked(LangOf(_catalog.CurrentLayoutId() ?? ""))
                                   : new PhraseTracker.WordKind.Neutral(), gen);
                break;
            }

            case Outcome.Defer defer:
            {
                // Reads as another language, but it is two or three letters long, so that reading is
                // worth very little — a quarter of two-letter Latin strings are in the English
                // dictionary. Leave the screen alone and remember the keystrokes as defaulted to the
                // current language: if a later word settles the phrase the other way, the correction
                // machinery converts this word along with it, and if none does, nothing was disturbed.
                var shown = _resolver.RenderCurrent(word) ?? defer.Original;
                var cur = LangOf(_catalog.CurrentLayoutId() ?? "");
                Diagnostics.Log($"  auto: \"{shown}\" reads as " +
                                string.Join("/", defer.Winners.Select(w => $"{w.Converted} [{w.Lang}]")) +
                                " — too short to act on, waiting for the phrase");
                _phrase.Record(word, shown, 1, new PhraseTracker.WordKind.Defaulted(cur), gen);

                // Count the run. Only an unambiguous reading counts: a word that could be two
                // languages says nothing about which one this phrase is in.
                var only = defer.Winners.Count == 1 ? defer.Winners[0] : null;
                if (only is null || only.Lang != _heldLang) { _heldLang = only?.Lang; _heldRun = only is null ? 0 : 1; }
                else _heldRun++;

                if (_heldRun >= HeldRunSettles && only is not null && !hardBoundary)
                    SettleHeldRun(only.Lang, only.LayoutId, gen);
                break;
            }

            case Outcome.Convert conv:
            {
                ForgetHeldRun();
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
                ForgetHeldRun();
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

        if (hardBoundary) ResetPhrase();
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
        // Unverified counts as applied: it means this target's text cannot be read back, not that the
        // rewrite failed. Anything else unproven would show "couldn't rewrite here" on every browser word.
        if (res is TextRewriter.Result.Ok or TextRewriter.Result.Unverified)
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
            ResetPhrase(); // screen state uncertain — drop phrase memory
        }
        else
        {
            Diagnostics.Log($"  auto: \"{d.Original}\" -> \"{d.Converted}\" : {res}");
            // A rewrite that landed wrong, or that could not be checked, leaves the screen in a state the
            // phrase tracker's model no longer describes — the same reasoning as an abort.
            if (res is TextRewriter.Result.Mismatch) ResetPhrase();
            NotifyFailure(res);
        }
    }

    /// <summary>Plain-language reason for a word being left alone, for the debug log.</summary>
    private static string Explain(KeepReason reason) => reason switch
    {
        KeepReason.ValidInCurrent => "already a word in this layout's language",
        KeepReason.NotAWordAnywhere => "not a word in any installed language",
        KeepReason.NoCurrentLanguage => "current layout has no usable language",
        KeepReason.LooksLikeATypo => "reads as another language, but this one has a word one key away "
                                     + "— treating it as a typo",
        KeepReason.PhraseDisagrees => "too short to decide, and the phrase reads as another language",
        _ => reason.ToString(),
    };

    /// <summary>
    /// Enough held words have agreed on the same language to act on them together. Convert the whole
    /// held run in one rewrite and treat the phrase as settled, so the words after it convert directly
    /// instead of piling up too.
    /// </summary>
    private void SettleHeldRun(string lang, string layoutId, int gen)
    {
        var corr = _phrase.BuildCorrection(lang, layoutId);
        if (corr is null) return;

        var res = ArmedRewrite(corr.OldSegment.Length, corr.NewSegment, corr.OldSegment);
        if (res is TextRewriter.Result.Ok or TextRewriter.Result.Unverified)
        {
            var prevLayout = _catalog.CurrentLayoutId();
            var path = LayoutSwitcher.SwitchForeground(layoutId);
            Diagnostics.Log($"  auto: {_heldRun} short words agree -> [{LangLabel(layoutId)}] " +
                            $"\"{corr.NewSegment.TrimEnd()}\" via {path} : {res}");
            _phrase.Confirm(corr, gen);
            _settledLang = lang;
            _heldLang = null;
            _heldRun = 0;
            RaiseConverted(corr.OldSegment.TrimEnd(), corr.NewSegment.TrimEnd(), layoutId);
            SeedCancelCycle(corr.OldSegment.TrimEnd(), corr.NewSegment.TrimEnd(), ' ', layoutId, prevLayout);
        }
        else
        {
            Diagnostics.Log($"  auto: held-run correction : {res}");
            if (res is TextRewriter.Result.Mismatch or TextRewriter.Result.Aborted) _phrase.Reset();
            ForgetHeldRun();
        }
    }

    /// <summary>Apply a phrase correction + the current word as one segment rewrite, then switch.</summary>
    private void ApplyCorrection(IReadOnlyList<TypedKey> word, Decision d, PhraseTracker.Correction corr,
                                 char boundary, string lang, int gen)
    {
        var oldSeg = corr.OldSegment + d.Original + boundary;
        var newSeg = corr.NewSegment + d.Converted + boundary;
        var res = ArmedRewrite(oldSeg.Length, newSeg, oldSeg);
        if (res is TextRewriter.Result.Ok or TextRewriter.Result.Unverified)
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
            ResetPhrase();
        }
        else
        {
            Diagnostics.Log($"  auto: phrase correction : {res}");
            if (res is TextRewriter.Result.Mismatch) ResetPhrase();
            NotifyFailure(res);
        }
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
                                 OnScreenLen = converted.Length + 1,
                                 OnScreenText = converted + boundary };
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
        // Nothing to switch between: one layout, or none whose language we have a dictionary for. This is
        // the state a fresh PC is in, and the state the Store reviewer tested in.
        if (UsableLayoutCount() < 2)
        {
            Diagnostics.Log("(only one usable layout — nothing to convert between)");
            RaiseHint("hint.setup.title", "hint.setup.body", "hint.setup.chip");
            return null;
        }

        var (cur, prev) = _monitor.Snapshot();

        // A live selection outranks the keystroke buffer, and not as a preference — as a safety rule.
        // The buffer path erases its recorded length at the caret with backspaces; with something
        // selected, the first backspace erases the selection instead and the remaining ones eat whatever
        // precedes it. That is how a selected line came to be replaced along with two characters of the
        // line above it. Every selection gesture now also clears the buffer, so this should be
        // unreachable — it stays because "should be" is what shipped the bug.
        // Buffer first: with nothing buffered the selection path runs anyway, so the probe would be wasted.
        if ((cur.Count > 0 || prev.Count > 0) && Selection.HasSelection() == true)
        {
            Diagnostics.Log("  buffer ignored — text is selected, converting the selection instead");
            cur = Array.Empty<TypedKey>();
            prev = Array.Empty<TypedKey>();
        }

        if (cur.Count > 0 || prev.Count > 0)
        {
            var word = cur.Count > 0 ? cur : prev;
            var suffix = cur.Count > 0 ? "" : " ";       // finished word: the boundary space is on screen
            var plan = _resolver.ManualPlan(word, word.Any(k => k.Caps), _settings.AmbiguousLang);
            if (plan is null)
            {
                Diagnostics.Log("(nothing to convert)");
                RaiseHint("hint.nothing.title", "hint.nothing.body", "hint.nothing.chip");
                return null;
            }
            return new Cycle { Plan = plan, Suffix = suffix, Step = 0,
                               OnScreenLen = (plan.Original + suffix).Length,
                               OnScreenText = plan.Original + suffix };
        }

        // Ask first, and only synthesize a copy if the answer is not a flat no. The clipboard probe can be
        // fooled into returning text nobody selected; a definite "nothing is selected" from the
        // accessibility tree keeps it from being asked at all.
        if (Selection.HasSelection() == false)
        {
            Diagnostics.Log($"(nothing selected — type a word or select text, then press {_settings.TriggerLabel})");
            RaiseHint("hint.nothing.title", "hint.type.body", "hint.type.chip", _settings.TriggerLabel);
            return null;
        }

        var selected = Selection.Read();
        if (selected is null)
        {
            Diagnostics.Log($"(type a word or select text, then press {_settings.TriggerLabel})");
            RaiseHint("hint.nothing.title", "hint.type.body", "hint.type.chip", _settings.TriggerLabel);
            return null;
        }
        if (selected.Length > Selection.MaxChars)
        {
            Diagnostics.Log($"  selection: {selected.Length} chars — too long, skipped");
            RaiseHint("hint.nothing.title", "hint.tooLong.body", "hint.tooLong.chip", Selection.MaxChars);
            return null;
        }
        var selPlan = SelectionPlan(selected);
        if (selPlan is null)
        {
            Diagnostics.Log($"  selection: \"{selected}\" — no other layout renders it differently");
            RaiseHint("hint.nothing.title", "hint.nothing.body", "hint.nothing.chip");
            return null;
        }
        Diagnostics.Log($"  selection: \"{selected}\" → {selPlan.Candidates.Count} candidate(s)");
        return new Cycle { Plan = selPlan, Suffix = "", Step = 0, OnScreenLen = selected.Length,
                           OnScreenText = selected, FromSelection = true };
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
        ResetPhrase();

        bool restore = cyc.Step >= cyc.Plan.Candidates.Count;
        string targetId = restore ? cyc.Plan.OriginalLayoutId : cyc.Plan.Candidates[cyc.Step].TargetLayoutId;
        string label = restore ? $"original:{LangLabel(cyc.Plan.OriginalLayoutId)}" : LangLabel(targetId);
        string text = (restore ? cyc.Plan.Original : cyc.Plan.Candidates[cyc.Step].Converted) + cyc.Suffix;

        var path = LayoutSwitcher.SwitchForeground(targetId);
        // A live selection is erased by a single backspace; afterwards we erase what we typed.
        int erase = cyc.FromSelection && cyc.Step == 0 ? 1 : cyc.OnScreenLen;
        var res = TextRewriter.Rewrite(erase, text, waitForKeyUpVk: _settings.TriggerKey,
                                       original: cyc.OnScreenText);
        Diagnostics.Log($"  cycle[{cyc.Step}] -> [{label}] \"{text.TrimEnd()}\" via {path} : {res}");

        // A step *proven* not to have landed ends the cycle instead of advancing it. The next step would
        // erase `text.Length` characters on the assumption that this one put them there, so continuing
        // from a screen we know is wrong is how one bad rewrite got worse with every further tap.
        // Starting afresh costs the user one tap; continuing costs them text.
        //
        // Unverified is deliberately NOT in that set. It means the target exposes no readable text, not
        // that anything went wrong — a Chromium text box answers nothing until its accessibility tree is
        // built. Treating it as a failure would put an error notification in front of every conversion in
        // a browser and break cycling there, inventing a fault where the measurement showed the text
        // landing correctly.
        if (res is TextRewriter.Result.Unverified)
            Diagnostics.Log("  cycle: continuing unverified — this target's text cannot be read back");
        else if (res is not TextRewriter.Result.Ok)
        {
            lock (_cycleLock) _cycle = null;
            if (res is TextRewriter.Result.Mismatch)
                Diagnostics.LogAlways("  cycle: abandoned after Mismatch — the next trigger will start from what is on screen");
            NotifyFailure(res);
            return;
        }
        // Feedback on manual conversions too, but not on the final restore-to-original step.
        else if (!restore) RaiseConverted(cyc.Plan.Original, text, targetId);
        // The restore step is the user rejecting a conversion — the moment to offer to remember it.
        // The first candidate is what had been on screen, so that is the word to suppress.
        else if (cyc.Plan.Candidates.Count > 0)
            Undone?.Invoke(cyc.Plan.Original.TrimEnd(), cyc.Plan.Candidates[0].Converted.TrimEnd());

        cyc.OnScreenLen = text.Length;
        cyc.OnScreenText = text;
        cyc.Step++;
        if (restore) lock (_cycleLock) _cycle = null; // full loop done; next F9 starts fresh
    }
}

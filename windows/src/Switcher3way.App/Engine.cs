using System.Collections.Concurrent;
using Switcher3way.Core;
using Switcher3way.Dictionaries;

namespace Switcher3way.App;

/// <summary>No user overrides yet (phase 5 wires real settings).</summary>
internal sealed class EmptyAlwaysConvert : IAlwaysConvertList
{
    public bool IsAlwaysConvert(string converted) => false;
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
    private readonly KeyboardMonitor _monitor = new();
    private readonly BlockingCollection<Action> _work = new();

    private volatile bool _converting;
    private readonly object _cycleLock = new();
    private Cycle? _cycle;

    private const int VK_F9 = 0x78;

    private sealed class Cycle
    {
        public required ManualPlan Plan;
        public required string Suffix;   // trailing boundary char to preserve (" " if word was finished)
        public int Step;                 // 0..Candidates.Count; == Count → restore original
        public int OnScreenLen;          // chars currently displayed for the token
    }

    public Engine()
    {
        _resolver = new NWayResolver(_catalog, _dict, new EmptyAlwaysConvert());
        _monitor.WordCompleted += (word, boundary) => _work.Add(() => AutoConvert(word, boundary));
        _monitor.TriggerPressed += OnTrigger;
        _monitor.QuitPressed += () => _work.CompleteAdding();
        _monitor.Typed += () => { lock (_cycleLock) _cycle = null; };
    }

    public void RunInteractive()
    {
        Console.WriteLine("=== Switcher3way (Windows) — live loop ===");
        Console.WriteLine("Auto-fixes finished words; F9 = manual convert/cycle; End = quit.\n");
        var hookThread = new Thread(_monitor.Run) { IsBackground = true, Name = "hook" };
        hookThread.SetApartmentState(ApartmentState.STA);
        hookThread.Start();

        foreach (var job in _work.GetConsumingEnumerable())
        {
            try { job(); }
            catch (Exception ex) { Console.WriteLine($"  [error] {ex.Message}"); }
        }
    }

    // ---- Auto path -------------------------------------------------------------------------
    private void AutoConvert(IReadOnlyList<TypedKey> word, char boundary)
    {
        bool caps = word.Any(k => k.Caps);
        var d = _resolver.Resolve(word, caps);
        if (d is null) return;

        var path = LayoutSwitcher.SwitchForeground(d.TargetLayoutId);
        // Same text in the target layout (e.g. Cyrillic that looks identical in uk vs ru): the
        // layout was wrong but the characters are already correct — switch, don't rewrite (avoids a
        // needless erase/retype).
        if (d.Converted == d.Original)
        {
            Console.WriteLine($"  auto: layout -> [{d.TargetLayoutId}] (text \"{d.Original}\" unchanged) via {path}");
            return;
        }
        // The boundary char is already on screen; erase word+boundary and re-type converted+boundary.
        var res = TextRewriter.Rewrite(word.Count + 1, d.Converted + boundary);
        Console.WriteLine($"  auto: \"{d.Original}\" -> \"{d.Converted}\" [{d.TargetLayoutId}] via {path} : {res}");
    }

    // ---- Manual N-way cycle ----------------------------------------------------------------
    private void OnTrigger()
    {
        if (_converting) return;   // ignore F9 auto-repeat / re-entrancy
        _converting = true;
        _work.Add(() => { try { ManualStep(); } finally { _converting = false; } });
    }

    private void ManualStep()
    {
        Cycle cyc;
        lock (_cycleLock)
        {
            if (_cycle is null)
            {
                var (cur, prev) = _monitor.Snapshot();
                IReadOnlyList<TypedKey> word;
                string suffix;
                if (cur.Count > 0) { word = cur; suffix = ""; }        // in-progress: caret after word
                else if (prev.Count > 0) { word = prev; suffix = " "; } // finished with a space
                else { Console.WriteLine("(type a word, then press F9)"); return; }

                var plan = _resolver.ManualPlan(word, word.Any(k => k.Caps));
                if (plan is null) { Console.WriteLine("(nothing to convert)"); return; }
                _cycle = new Cycle { Plan = plan, Suffix = suffix, Step = 0, OnScreenLen = (plan.Original + suffix).Length };
            }
            cyc = _cycle;
        }

        bool restore = cyc.Step >= cyc.Plan.Candidates.Count;
        string targetId = restore ? cyc.Plan.OriginalLayoutId : cyc.Plan.Candidates[cyc.Step].TargetLayoutId;
        string label = restore ? "original" : cyc.Plan.Candidates[cyc.Step].TargetLayoutId;
        string text = (restore ? cyc.Plan.Original : cyc.Plan.Candidates[cyc.Step].Converted) + cyc.Suffix;

        var path = LayoutSwitcher.SwitchForeground(targetId);
        var res = TextRewriter.Rewrite(cyc.OnScreenLen, text, waitForKeyUpVk: VK_F9);
        Console.WriteLine($"  cycle[{cyc.Step}] -> [{label}] \"{text.TrimEnd()}\" via {path} : {res}");

        cyc.OnScreenLen = text.Length;
        cyc.Step++;
        if (restore) lock (_cycleLock) _cycle = null; // full loop done; next F9 starts fresh
    }
}

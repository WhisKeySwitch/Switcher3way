using System.Collections.Concurrent;
using Switcher3wSpike;

// ---------------------------------------------------------------------------------------------
// Switcher3way Windows feasibility SPIKE (throwaway). See design.md / FINDINGS.md.
//
//   dotnet run -- selftest    Non-interactive: enumerate layouts + render a sample word through
//                             each, exercise the dead-key flush. Safe to run headless.
//   dotnet run                Interactive: install a global keyboard hook. Type in Notepad; on
//                             each finished word the spike prints how every layout would render
//                             it. Press PAUSE/BREAK to convert the last word into the first
//                             differently-languaged layout (switch foreground layout + rewrite).
//                             Press END to quit.
// ---------------------------------------------------------------------------------------------

if (args.Length > 0 && args[0].Equals("selftest", StringComparison.OrdinalIgnoreCase))
{
    SelfTest.Run();
    return;
}

Interactive.Run();

// ---------------------------------------------------------------------------------------------

internal static class SelfTest
{
    private static int _pass, _fail, _skip;

    public static void Run()
    {
        Console.WriteLine("=== Switcher3way Windows spike — SELF TEST (no hook) ===\n");

        var layouts = LayoutRenderer.InstalledLayouts();
        Console.WriteLine($"Installed layouts ({layouts.Count}):");
        foreach (var l in layouts)
            Console.WriteLine($"  HKL=0x{(long)l.Hkl:X8}  lang={l.LangTag}  usable={LayoutRenderer.HasUsableLanguage(l)}");
        Check("at least one usable layout", layouts.Any(LayoutRenderer.HasUsableLanguage));

        // --- Classifier table (buffer-reset guards) ------------------------------------------
        Console.WriteLine("\nKey classification:");
        Check("A is Letter",       KeyClassifier.Classify('A') == KeyKind.Letter);
        Check("Space is Boundary", KeyClassifier.Classify(0x20) == KeyKind.Boundary);
        Check("Enter is Boundary", KeyClassifier.Classify(0x0D) == KeyKind.Boundary);
        Check("Backspace pops",    KeyClassifier.Classify(0x08) == KeyKind.Backspace);
        Check("Shift is Modifier",   KeyClassifier.Classify(0x10) == KeyKind.Modifier);
        Check("Left arrow Resets",   KeyClassifier.Classify(0x25) == KeyKind.Reset);
        Check("Digit 1 is Character",KeyClassifier.Classify('1') == KeyKind.Character);
        Check("Comma is Character",  KeyClassifier.Classify(0xBC) == KeyKind.Character); // ',' == 'б' on ЙЦУКЕН
        Check("F5 Resets",           KeyClassifier.Classify(0x74) == KeyKind.Reset);

        // --- Rendering: physical keys G,H,B,D,T,N through every usable layout ------------------
        uint[] word = { 'G', 'H', 'B', 'D', 'T', 'N' };
        Console.WriteLine("\nRendering physical keys G,H,B,D,T,N through every usable layout:");
        foreach (var (layout, text) in LayoutRenderer.RenderAll(word))
            Console.WriteLine($"  {layout.LangTag,-10} => \"{text}\"");

        var en = layouts.FirstOrDefault(l => l.LangTag.StartsWith("en", StringComparison.Ordinal));
        var ru = layouts.FirstOrDefault(l => l.LangTag.StartsWith("ru", StringComparison.Ordinal));
        var uk = layouts.FirstOrDefault(l => l.LangTag.StartsWith("uk", StringComparison.Ordinal));
        CheckOrSkip("en-* renders \"ghbdtn\"", en.Hkl != IntPtr.Zero, () => LayoutRenderer.RenderWord(word, en.Hkl) == "ghbdtn");
        CheckOrSkip("ru-* renders \"привет\"", ru.Hkl != IntPtr.Zero, () => LayoutRenderer.RenderWord(word, ru.Hkl) == "привет");

        // Regression for the comma bug: physical keys d,b,COMMA,f,x,n,t must render "вибачте"
        // (the ',' key is 'б'). Before the fix the comma reset the buffer and this was impossible.
        uint[] vybachte = { 'D', 'B', 0xBC, 'F', 'X', 'N', 'T' };
        Console.WriteLine("\nComma-in-word (db,fxnt) rendering:");
        foreach (var (layout, text) in LayoutRenderer.RenderAll(vybachte))
            Console.WriteLine($"  {layout.LangTag,-10} => \"{text}\"");
        CheckOrSkip("uk-* renders \"вибачте\" (comma is a letter)", uk.Hkl != IntPtr.Zero, () => LayoutRenderer.RenderWord(vybachte, uk.Hkl) == "вибачте");

        // --- Shift fidelity: Shift on the first key yields a capital -------------------------
        if (ru.Hkl != IntPtr.Zero)
        {
            var shifted = new List<LayoutRenderer.BufferedKey>
            {
                new('G', 0, true), new('H', 0, false), new('B', 0, false),
                new('D', 0, false), new('T', 0, false), new('N', 0, false),
            };
            string cap = LayoutRenderer.RenderWord(shifted, ru.Hkl);
            Console.WriteLine($"\nShift fidelity: Shift+G,h,b,d,t,n on ru-* => \"{cap}\"");
            Check("shifted first key capitalizes (Привет)", cap == "Привет");
        }
        else Skip("shifted first key capitalizes (Привет)");

        // --- Dead-key safety (R3): render twice; results must match --------------------------
        Console.WriteLine("\nDead-key flush check (render twice; results must match):");
        foreach (var l in layouts)
        {
            if (!LayoutRenderer.HasUsableLanguage(l)) continue;
            string a = LayoutRenderer.RenderWord(word, l.Hkl);
            string b = LayoutRenderer.RenderWord(word, l.Hkl);
            Console.WriteLine($"  {l.LangTag,-10} pass1=\"{a}\" pass2=\"{b}\"  {(a == b ? "OK" : "MISMATCH!")}");
            Check($"{l.LangTag} stable across re-render", a == b);
        }

        Console.WriteLine($"\n=== SELF TEST: {_pass} passed, {_fail} failed, {_skip} skipped ===");
        Console.WriteLine("Interactive hook/switch/rewrite require `dotnet run` at a real keyboard.");
        if (_fail > 0) Environment.ExitCode = 1;
    }

    private static void Check(string name, bool ok)
    {
        Console.WriteLine($"  [{(ok ? "PASS" : "FAIL")}] {name}");
        if (ok) _pass++; else _fail++;
    }

    private static void CheckOrSkip(string name, bool applicable, Func<bool> test)
    {
        if (!applicable) { Skip(name); return; }
        Check(name, test());
    }

    private static void Skip(string name)
    {
        Console.WriteLine($"  [SKIP] {name} (layout not installed)");
        _skip++;
    }
}

internal static class Interactive
{
    // Buffered keystrokes (vk + real scancode + shift) for the current and previous word.
    private static readonly List<LayoutRenderer.BufferedKey> CurrentWord = new();
    private static readonly List<LayoutRenderer.BufferedKey> PrevWord = new();
    private static readonly object BufferLock = new();

    // Work marshalled off the hook thread (switch + rewrite must not run inside the callback).
    private static readonly BlockingCollection<Action> Work = new();

    private static IntPtr _hook;
    private static Native.LowLevelKeyboardProc? _proc; // keep the delegate alive

    private const uint VK_TRIGGER = 0x78; // F9 (present on laptops; swallowed so it can't leak)
    private const uint VK_QUIT = 0x23;    // END

    public static void Run()
    {
        Console.WriteLine("=== Switcher3way Windows spike — INTERACTIVE ===");
        Console.WriteLine("Type words in another app (Notepad). Each finished word prints its per-layout renderings.");
        Console.WriteLine("F9 = convert the word you just typed; press F9 again to cycle layouts (…->ru->uk->original).");
        Console.WriteLine("Typing anything starts a fresh word. END = quit.\n");

        var hookThread = new Thread(HookThreadMain) { IsBackground = true, Name = "hook" };
        hookThread.SetApartmentState(ApartmentState.STA);
        hookThread.Start();

        // Main thread drains the work queue (switch + rewrite, which use Sleep and must be off the hook).
        foreach (var job in Work.GetConsumingEnumerable())
        {
            try { job(); }
            catch (Exception ex) { Console.WriteLine($"  [work error] {ex.Message}"); }
        }
    }

    private static void HookThreadMain()
    {
        _proc = HookCallback;
        _hook = Native.SetWindowsHookEx(Native.WH_KEYBOARD_LL, _proc, Native.GetModuleHandle(null), 0);
        if (_hook == IntPtr.Zero)
        {
            Console.WriteLine("Failed to install WH_KEYBOARD_LL hook.");
            Work.CompleteAdding();
            return;
        }

        // Message pump — required for LL hook callbacks to be delivered (S2).
        while (Native.GetMessage(out var msg, IntPtr.Zero, 0, 0) > 0)
        {
            Native.TranslateMessage(ref msg);
            Native.DispatchMessage(ref msg);
        }
        Native.UnhookWindowsHookEx(_hook);
    }

    private static IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0 && (wParam == Native.WM_KEYDOWN || wParam == Native.WM_SYSKEYDOWN))
        {
            var data = System.Runtime.InteropServices.Marshal.PtrToStructure<Native.KBDLLHOOKSTRUCT>(lParam);
            // Ignore our OWN synthesized keystrokes (backspaces + Unicode from the rewrite); otherwise
            // the hook re-processes them and can corrupt the buffer/output.
            bool injected = (data.flags & Native.LLKHF_INJECTED) != 0;
            if (!injected && HandleKeyDown(data)) return (IntPtr)1; // swallow control keys (F9/End)
        }
        return Native.CallNextHookEx(_hook, nCode, wParam, lParam);
    }

    /// <summary>Returns true if the key is one of the spike's control keys and should be swallowed.</summary>
    private static bool HandleKeyDown(Native.KBDLLHOOKSTRUCT data)
    {
        uint vk = data.vkCode;

        // Intercept the spike's own control keys before normal classification (and swallow them).
        if (vk == VK_QUIT)
        {
            Console.WriteLine("Quitting.");
            Work.CompleteAdding();
            Native.PostQuitMessage(0);
            return true;
        }
        if (vk == VK_TRIGGER) { TriggerConvert(); return true; }

        var kind = KeyClassifier.Classify(vk);
        if (kind != KeyKind.Modifier) lock (BufferLock) { _cycle = null; } // any real keystroke ends a cycle

        switch (kind)
        {
            case KeyKind.Letter:
            case KeyKind.Character:
                bool shift = (Native.GetAsyncKeyState((int)Native.VK_SHIFT) & 0x8000) != 0;
                lock (BufferLock) CurrentWord.Add(new LayoutRenderer.BufferedKey(vk, data.scanCode, shift));
                break;

            case KeyKind.Boundary:
                CompleteWord();
                break;

            case KeyKind.Backspace:
                // In-place edit: drop the last buffered key rather than discarding the whole word.
                lock (BufferLock) { if (CurrentWord.Count > 0) CurrentWord.RemoveAt(CurrentWord.Count - 1); }
                break;

            case KeyKind.Modifier:
                break; // bare modifier: keep the buffer intact

            case KeyKind.Reset:
                // Cursor movement / editing / unexpected key: discard so a later rewrite can't
                // delete unrelated text (spec: reset on unsafe cursor movement).
                lock (BufferLock) CurrentWord.Clear();
                break;
        }
        return false; // let normal keystrokes pass through to the app
    }

    private static void CompleteWord()
    {
        List<LayoutRenderer.BufferedKey> finished;
        lock (BufferLock)
        {
            if (CurrentWord.Count == 0) return;
            finished = new List<LayoutRenderer.BufferedKey>(CurrentWord);
            PrevWord.Clear();
            PrevWord.AddRange(CurrentWord);
            CurrentWord.Clear();
        }

        Console.WriteLine($"buffered: {KeysToString(finished)} ({finished.Count} keys)");
        foreach (var (layout, text) in LayoutRenderer.RenderAll(finished))
            Console.WriteLine($"  rendered[{layout.LangTag}] = \"{text}\"");
    }

    private static volatile bool _converting;

    /// <summary>State for the N-way manual cycle: repeated F9 with no typing between steps advances
    /// through every candidate layout and finally restores the original text + layout.</summary>
    private sealed class Cycle
    {
        public required List<LayoutRenderer.BufferedKey> Word;
        public required IntPtr OriginalHkl;
        public required List<LayoutRenderer.Layout> Candidates; // layouts != original
        public required string Suffix;   // trailing boundary char to preserve (e.g. " "), or ""
        public int Step;                 // 0..Candidates.Count; == Count means "restore original"
        public int OnScreenLen;          // chars currently displayed for this token
    }
    private static Cycle? _cycle;

    private static void TriggerConvert()
    {
        // Ignore F9 auto-repeat / re-entrancy while a conversion is already running.
        if (_converting) return;

        // Starting a fresh cycle needs a buffered word; continuing one does not.
        List<LayoutRenderer.BufferedKey>? seed = null;
        string seedSuffix = "";
        lock (BufferLock)
        {
            if (_cycle == null)
            {
                if (CurrentWord.Count > 0) { seed = new(CurrentWord); seedSuffix = ""; }       // in-progress, caret after word
                else if (PrevWord.Count > 0) { seed = new(PrevWord); seedSuffix = " "; }        // finished with a space
                else { Console.WriteLine("(type a word, then press F9)"); return; }
                CurrentWord.Clear(); PrevWord.Clear();
            }
        }
        _converting = true;

        Work.Add(() =>
        {
          try
          {
            var fg = LayoutSwitcher.Foreground();

            // Build the cycle on the first F9 for this word.
            if (_cycle == null)
            {
                IntPtr orig = Native.GetKeyboardLayout(fg.ThreadId);
                var candidates = LayoutRenderer.InstalledLayouts()
                    .Where(l => LayoutRenderer.HasUsableLanguage(l) && l.Hkl != orig).ToList();
                if (candidates.Count == 0) { Console.WriteLine("  (no alternative layout installed)"); return; }
                string origText = LayoutRenderer.RenderWord(seed!, orig) + seedSuffix;
                lock (BufferLock)
                    _cycle = new Cycle { Word = seed!, OriginalHkl = orig, Candidates = candidates,
                                         Suffix = seedSuffix, Step = 0, OnScreenLen = origText.Length };
            }

            var c = _cycle!;
            bool restore = c.Step >= c.Candidates.Count;
            IntPtr targetHkl = restore ? c.OriginalHkl : c.Candidates[c.Step].Hkl;
            string label = restore ? "original" : c.Candidates[c.Step].LangTag;
            string newText = LayoutRenderer.RenderWord(c.Word, targetHkl) + c.Suffix;

            Console.WriteLine($"  cycle[{c.Step}] -> [{label}] \"{newText}\" in {fg.Exe}");
            var path = LayoutSwitcher.SwitchForeground(targetHkl);
            Console.WriteLine($"  switched via {path}");
            var result = TextRewriter.Rewrite(c.OnScreenLen, newText);
            Console.WriteLine(result switch
            {
                TextRewriter.Result.Ok => "  rewrote OK",
                TextRewriter.Result.Protected => "  PROTECTED (elevated/UIPI target — not rewritten)",
                _ => "  PARTIAL injection (treated as protected)",
            });

            c.OnScreenLen = newText.Length;
            c.Step++;
            if (restore) lock (BufferLock) { _cycle = null; } // full loop done; next F9 starts fresh
          }
          finally { _converting = false; }
        });
    }

    private static string KeysToString(IReadOnlyList<LayoutRenderer.BufferedKey> keys)
        => new string(keys.Select(k => (char)k.Vk).ToArray());
}

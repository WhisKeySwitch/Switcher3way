using System.Runtime.InteropServices;
using Switcher3way.Core;

namespace Switcher3way.App;

/// <summary>
/// Global low-level keyboard hook + word buffer. Buffers letters/digits/OEM keys into the current
/// word (recording shift + caps), detects boundaries, and raises events. Ignores its
/// own synthesized input (tagged via <c>dwExtraInfo</c>) and swallows the control keys. Graduated from
/// the spike.
/// </summary>
internal sealed class KeyboardMonitor
{
    private readonly SettingsManager _settings;
    public KeyboardMonitor(SettingsManager settings) => _settings = settings;

    private readonly List<TypedKey> _current = new();
    private readonly List<TypedKey> _prev = new();
    private readonly object _lock = new();

    private IntPtr _hook, _mouseHook, _winEventHook;
    private Native.LowLevelKeyboardProc? _proc, _mouseProc; // keep the delegates alive
    private Native.WinEventProc? _winEventProc;
    private IntPtr _bufferHwnd; // the foreground window the current buffer belongs to

    // Double-tap trigger state (e.g. the default double Ctrl).
    private bool _triggerHeld, _otherBetween;
    private long _lastTapMs;
    private const long DoubleTapMs = 350;

    /// <summary>A word finished at a boundary: the keys + the boundary char (' ', '\n', '\t').</summary>
    public event Action<IReadOnlyList<TypedKey>, char>? WordCompleted;
    /// <summary>The manual trigger (whatever key the settings name) was pressed.</summary>
    public event Action? TriggerPressed;
    /// <summary>Any real keystroke (not the trigger) — used to reset an in-progress manual cycle.</summary>
    public event Action? Typed;
    /// <summary>The foreground window changed (for per-app layout memory). Carries the new hwnd.</summary>
    public event Action<IntPtr>? ForegroundChanged;
    /// <summary>A hard reset of the phrase (arrows / click / app switch / backspace into a prior word).</summary>
    public event Action? PhraseReset;
    /// <summary>A boundary space arrived with no pending word (double space) — keeps phrase math exact.</summary>
    public event Action? ExtraSpace;

    // Abort guard for in-flight rewrites: a real keystroke while a rewrite is armed aborts it, so a
    // longer multi-word correction can't be corrupted by concurrent typing.
    private volatile bool _rewriting;
    private volatile bool _aborted;
    /// <summary>Arm the abort guard around a rewrite (clears the aborted flag).</summary>
    public void ArmRewrite() { _aborted = false; _rewriting = true; }
    /// <summary>Disarm the abort guard once the rewrite finished.</summary>
    public void DisarmRewrite() => _rewriting = false;
    /// <summary>True if a real keystroke arrived since the rewrite was armed.</summary>
    public bool RewriteAborted => _aborted;

    /// <summary>Thread-safe snapshot of the current (in-progress) and previous (completed) words.</summary>
    public (IReadOnlyList<TypedKey> Current, IReadOnlyList<TypedKey> Prev) Snapshot()
    {
        lock (_lock)
        {
            // If focus moved since the buffer was filled (e.g. Alt+Tab, no click), it's stale.
            if (_bufferHwnd != IntPtr.Zero && Native.GetForegroundWindow() != _bufferHwnd)
            {
                _current.Clear(); _prev.Clear(); _bufferHwnd = IntPtr.Zero;
                return (Array.Empty<TypedKey>(), Array.Empty<TypedKey>());
            }
            return (new List<TypedKey>(_current), new List<TypedKey>(_prev));
        }
    }

    /// <summary>Installs the hook and runs the message pump (blocks — call on a dedicated STA thread).</summary>
    public void Run()
    {
        IntPtr hmod = Native.GetModuleHandle(null);
        _proc = HookCallback;
        _hook = Native.SetWindowsHookEx(Native.WH_KEYBOARD_LL, _proc, hmod, 0);
        _mouseProc = MouseCallback;
        _mouseHook = Native.SetWindowsHookEx(Native.WH_MOUSE_LL, _mouseProc, hmod, 0); // clears buffer on clicks
        _winEventProc = WinEventCallback;
        _winEventHook = Native.SetWinEventHook(Native.EVENT_SYSTEM_FOREGROUND, Native.EVENT_SYSTEM_FOREGROUND,
            IntPtr.Zero, _winEventProc, 0, 0, Native.WINEVENT_OUTOFCONTEXT); // foreground change → per-app memory
        if (_hook == IntPtr.Zero) { Console.WriteLine("Failed to install WH_KEYBOARD_LL hook."); return; }
        while (Native.GetMessage(out var msg, IntPtr.Zero, 0, 0) > 0)
        {
            Native.TranslateMessage(ref msg);
            Native.DispatchMessage(ref msg);
        }
        Native.UnhookWindowsHookEx(_hook);
        if (_mouseHook != IntPtr.Zero) Native.UnhookWindowsHookEx(_mouseHook);
        if (_winEventHook != IntPtr.Zero) Native.UnhookWinEvent(_winEventHook);
    }

    private void WinEventCallback(IntPtr hHook, uint ev, IntPtr hwnd, int idObject, int idChild, uint thread, uint time)
    {
        if (hwnd == IntPtr.Zero) return;
        ClearBuffer("foreground change");                  // app switch → the buffer is stale (unsafe cursor context)
        ForegroundChanged?.Invoke(hwnd);
    }

    // A mouse click may move the caret or select text → the word buffer no longer matches the
    // caret, so discard it (mirrors the macOS "reset on mouse" guard). This is what stops F9 from
    // deleting a selection after you click.
    private IntPtr MouseCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            uint msg = (uint)wParam;
            if (msg is Native.WM_LBUTTONDOWN or Native.WM_RBUTTONDOWN or Native.WM_MBUTTONDOWN or Native.WM_XBUTTONDOWN)
                ClearBuffer("mouse click");
        }
        return Native.CallNextHookEx(_mouseHook, nCode, wParam, lParam);
    }

    private void ClearBuffer(string reason = "?")
    {
        Diagnostics.Log($"  buf: cleared ({reason})");
        lock (_lock) { _current.Clear(); _prev.Clear(); _bufferHwnd = IntPtr.Zero; }
        Typed?.Invoke();        // also end any in-progress manual cycle
        PhraseReset?.Invoke();  // click / app switch ends the phrase
    }

    private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            uint msg = (uint)wParam;
            var data = Marshal.PtrToStructure<Native.KBDLLHOOKSTRUCT>(lParam);
            // Ignore only what *we* synthesized, identified by the tag we stamp into dwExtraInfo — not
            // everything carrying LLKHF_INJECTED. That broader test also excluded Remote Desktop, virtual
            // machines, remote-support tools, keyboard remappers and the on-screen keyboard, so the app
            // was inert wherever input did not come from a directly attached keyboard: keystrokes never
            // reached the buffer, the trigger press was invisible, and it looked dead.
            bool ours = data.dwExtraInfo == Native.OwnInputTag;
            if (!ours)
            {
                if (msg == Native.WM_KEYDOWN || msg == Native.WM_SYSKEYDOWN)
                { if (HandleKeyDown(data)) return (IntPtr)1; }          // swallow control keys
                else if (msg == Native.WM_KEYUP || msg == Native.WM_SYSKEYUP)
                { HandleKeyUp(data); }
            }
        }
        return Native.CallNextHookEx(_hook, nCode, wParam, lParam);
    }

    /// <summary>Returns true if the key is a control key to swallow.</summary>
    private bool HandleKeyDown(Native.KBDLLHOOKSTRUCT data)
    {
        uint vk = data.vkCode;

        if (_settings.TriggerDoubleTap)
        {
            if (NormVk(vk) == (uint)_settings.TriggerKey)
            {
                if (!_triggerHeld) // ignore auto-repeat while held
                {
                    _triggerHeld = true;
                    long now = Environment.TickCount64;
                    if (_lastTapMs != 0 && now - _lastTapMs <= DoubleTapMs && !_otherBetween)
                    {
                        _lastTapMs = 0;
                        TriggerPressed?.Invoke();
                    }
                    else { _lastTapMs = now; }
                    _otherBetween = false;
                }
                return false; // never swallow a modifier
            }
            _otherBetween = true; // any non-trigger key breaks the double-tap sequence
        }
        else if (vk == (uint)_settings.TriggerKey)
        {
            TriggerPressed?.Invoke();
            return true; // swallow the dedicated trigger key
        }

        var kind = KeyClassifier.Classify(vk);

        // A Ctrl/Alt chord is a command, not typing — Ctrl+A selects, Ctrl+V pastes, Ctrl+Z undoes,
        // Ctrl+X cuts, Alt+Tab leaves — and every one of those changes the text or the selection, so
        // nothing buffered still describes what sits at the caret. Buffering the letter instead is how
        // "Ctrl+A, then the trigger" replaced an entire document with one word: the 'a' became the word
        // to convert, and the rewrite's first backspace erased everything that was selected. Alt+Tab was
        // worse in a quieter way: Tab is a word boundary, so leaving an app finished the word.
        // AltGr arrives as Ctrl+Alt and does produce characters, so it is typing, not a command.
        if (kind != KeyKind.Modifier)
        {
            Typed?.Invoke();              // any real keystroke ends a manual cycle
            if (_rewriting) _aborted = true; // ...and aborts an in-flight rewrite

            bool ctrl = (Native.GetAsyncKeyState((int)Native.VK_CONTROL) & 0x8000) != 0;
            bool alt = (Native.GetAsyncKeyState((int)Native.VK_MENU) & 0x8000) != 0;
            if (ctrl ^ alt) { ClearBuffer("command chord"); return false; }
        }

        switch (kind)
        {
            case KeyKind.Letter:
            case KeyKind.Character:
                bool shift = (Native.GetAsyncKeyState((int)Native.VK_SHIFT) & 0x8000) != 0;
                bool caps = (Native.GetAsyncKeyState((int)Native.VK_CAPITAL) & 0x0001) != 0;
                int n;
                lock (_lock)
                {
                    _current.Add(new TypedKey((int)vk, shift, caps));
                    _bufferHwnd = Native.GetForegroundWindow();
                    n = _current.Count;
                }
                // Length only, never the key itself. This runs on the hook for every keystroke, long
                // before anything knows whether the focused field is a password — logging vk codes here
                // meant that switching on "debug logging" wrote down everything typed, including
                // credentials, in trivially decodable form. The buffer length is what the reset guards
                // actually need to be diagnosable; the conversion decision logs the word, and that path
                // is already blocked for password fields.
                Diagnostics.Log($"  buf: +1 (len={n})");
                break;
            case KeyKind.Boundary:
                CompleteWord(vk);
                break;
            case KeyKind.Backspace:
                bool intoPrev;
                lock (_lock)
                {
                    if (_current.Count > 0) { _current.RemoveAt(_current.Count - 1); intoPrev = false; }
                    else intoPrev = true;
                }
                // Backspacing past the start of the word edits the *finished* one, so its recorded form
                // is now one character longer than what is on screen. Keeping it meant the trigger
                // erased that phantom character too, eating whatever preceded it.
                if (intoPrev) ClearBuffer("backspaced into an earlier word");
                break;
            case KeyKind.Modifier:
                break;
            case KeyKind.Reset:
                // Arrows / Home / End / PageUp-Down / Ins / Del moved the caret, so BOTH buffers are
                // stale — not just the word in progress. Clearing only `_current` left the last
                // *finished* word eligible for the trigger, which then erased that word's length at the
                // new caret position: select a line with Shift+Home, tap the trigger, and it erased the
                // selection plus two characters of the line above it. Whatever is buffered is only ever
                // safe to rewrite while the caret has not moved since it was typed.
                ClearBuffer("caret moved");  // also ends the phrase
                break;
        }
        return false;
    }

    private void HandleKeyUp(Native.KBDLLHOOKSTRUCT data)
    {
        if (_settings.TriggerDoubleTap && NormVk(data.vkCode) == (uint)_settings.TriggerKey)
            _triggerHeld = false;
    }

    /// <summary>Map left/right modifier virtual keys to their generic code (LShift/RShift → Shift, …).</summary>
    private static uint NormVk(uint vk) => vk switch
    {
        0xA0 or 0xA1 => 0x10, // Shift
        0xA2 or 0xA3 => 0x11, // Ctrl
        0xA4 or 0xA5 => 0x12, // Alt
        _ => vk,
    };

    private void CompleteWord(uint boundaryVk)
    {
        List<TypedKey>? finished = null;
        bool extraSpace = false, focusMoved = false;
        lock (_lock)
        {
            if (_current.Count == 0)
            {
                extraSpace = boundaryVk == 0x20; // double space → note it for phrase math
            }
            // Focus moved since the word was typed → caret no longer matches the buffer; drop it.
            else if (_bufferHwnd != IntPtr.Zero && Native.GetForegroundWindow() != _bufferHwnd)
            {
                Diagnostics.Log($"  buf: dropped at boundary — focus moved (buf hwnd {_bufferHwnd:X}, fg {Native.GetForegroundWindow():X})");
                _current.Clear(); _prev.Clear(); _bufferHwnd = IntPtr.Zero; focusMoved = true;
            }
            else
            {
                finished = new List<TypedKey>(_current);
                _prev.Clear(); _prev.AddRange(_current); _current.Clear();
            }
        }
        // Fire outside the lock (handlers may re-enter the monitor's public surface).
        if (extraSpace) { ExtraSpace?.Invoke(); return; }
        if (focusMoved || finished is null) return;
        char boundary = boundaryVk switch { 0x0D => '\n', 0x09 => '\t', _ => ' ' };
        WordCompleted?.Invoke(finished, boundary);
    }
}

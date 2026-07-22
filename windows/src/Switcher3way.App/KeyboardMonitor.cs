using System.Runtime.InteropServices;
using Switcher3way.Core;

namespace Switcher3way.App;

/// <summary>
/// Global low-level keyboard hook + word buffer. Buffers letters/digits/OEM keys into the current
/// word (recording shift + caps), detects boundaries, and raises events. Ignores its own
/// synthesized input (<c>LLKHF_INJECTED</c>) and swallows the control keys. Graduated from the spike.
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

    // Double-tap trigger state (e.g. double Shift).
    private bool _triggerHeld, _otherBetween;
    private long _lastTapMs;
    private const long DoubleTapMs = 350;

    /// <summary>A word finished at a boundary: the keys + the boundary char (' ', '\n', '\t').</summary>
    public event Action<IReadOnlyList<TypedKey>, char>? WordCompleted;
    /// <summary>Manual trigger (F9) pressed.</summary>
    public event Action? TriggerPressed;
    /// <summary>Any real keystroke (not the trigger) — used to reset an in-progress manual cycle.</summary>
    public event Action? Typed;
    /// <summary>The foreground window changed (for per-app layout memory). Carries the new hwnd.</summary>
    public event Action<IntPtr>? ForegroundChanged;

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
        ClearBuffer();                  // app switch → the buffer is stale (unsafe cursor context)
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
                ClearBuffer();
        }
        return Native.CallNextHookEx(_mouseHook, nCode, wParam, lParam);
    }

    private void ClearBuffer()
    {
        lock (_lock) { _current.Clear(); _prev.Clear(); _bufferHwnd = IntPtr.Zero; }
        Typed?.Invoke(); // also end any in-progress manual cycle
    }

    private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            uint msg = (uint)wParam;
            var data = Marshal.PtrToStructure<Native.KBDLLHOOKSTRUCT>(lParam);
            bool injected = (data.flags & Native.LLKHF_INJECTED) != 0; // ignore our own SendInput
            if (!injected)
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
        if (kind != KeyKind.Modifier) Typed?.Invoke(); // any real keystroke ends a manual cycle

        switch (kind)
        {
            case KeyKind.Letter:
            case KeyKind.Character:
                bool shift = (Native.GetAsyncKeyState((int)Native.VK_SHIFT) & 0x8000) != 0;
                bool caps = (Native.GetAsyncKeyState((int)Native.VK_CAPITAL) & 0x0001) != 0;
                lock (_lock) { _current.Add(new TypedKey((int)vk, shift, caps)); _bufferHwnd = Native.GetForegroundWindow(); }
                break;
            case KeyKind.Boundary:
                CompleteWord(vk);
                break;
            case KeyKind.Backspace:
                lock (_lock) { if (_current.Count > 0) _current.RemoveAt(_current.Count - 1); }
                break;
            case KeyKind.Modifier:
                break;
            case KeyKind.Reset:
                lock (_lock) _current.Clear();
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
        List<TypedKey> finished;
        lock (_lock)
        {
            if (_current.Count == 0) return;
            // Focus moved since the word was typed → caret no longer matches the buffer; drop it.
            if (_bufferHwnd != IntPtr.Zero && Native.GetForegroundWindow() != _bufferHwnd)
            { _current.Clear(); _prev.Clear(); _bufferHwnd = IntPtr.Zero; return; }
            finished = new List<TypedKey>(_current);
            _prev.Clear(); _prev.AddRange(_current); _current.Clear();
        }
        char boundary = boundaryVk switch { 0x0D => '\n', 0x09 => '\t', _ => ' ' };
        WordCompleted?.Invoke(finished, boundary);
    }
}

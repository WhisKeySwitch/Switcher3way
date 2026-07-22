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
    private const uint VK_TRIGGER = 0x78; // F9 (present on laptops; swallowed)
    private const uint VK_QUIT = 0x23;    // End

    private readonly List<TypedKey> _current = new();
    private readonly List<TypedKey> _prev = new();
    private readonly object _lock = new();

    private IntPtr _hook, _mouseHook;
    private Native.LowLevelKeyboardProc? _proc, _mouseProc; // keep the delegates alive
    private IntPtr _bufferHwnd; // the foreground window the current buffer belongs to

    /// <summary>A word finished at a boundary: the keys + the boundary char (' ', '\n', '\t').</summary>
    public event Action<IReadOnlyList<TypedKey>, char>? WordCompleted;
    /// <summary>Manual trigger (F9) pressed.</summary>
    public event Action? TriggerPressed;
    /// <summary>Quit key (End) pressed.</summary>
    public event Action? QuitPressed;
    /// <summary>Any real keystroke (not the trigger) — used to reset an in-progress manual cycle.</summary>
    public event Action? Typed;

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
        if (_hook == IntPtr.Zero) { Console.WriteLine("Failed to install WH_KEYBOARD_LL hook."); return; }
        while (Native.GetMessage(out var msg, IntPtr.Zero, 0, 0) > 0)
        {
            Native.TranslateMessage(ref msg);
            Native.DispatchMessage(ref msg);
        }
        Native.UnhookWindowsHookEx(_hook);
        if (_mouseHook != IntPtr.Zero) Native.UnhookWindowsHookEx(_mouseHook);
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
        if (nCode >= 0 && ((uint)wParam == Native.WM_KEYDOWN || (uint)wParam == Native.WM_SYSKEYDOWN))
        {
            var data = Marshal.PtrToStructure<Native.KBDLLHOOKSTRUCT>(lParam);
            bool injected = (data.flags & Native.LLKHF_INJECTED) != 0; // ignore our own SendInput
            if (!injected && HandleKeyDown(data)) return (IntPtr)1;     // swallow control keys
        }
        return Native.CallNextHookEx(_hook, nCode, wParam, lParam);
    }

    /// <summary>Returns true if the key is a control key to swallow.</summary>
    private bool HandleKeyDown(Native.KBDLLHOOKSTRUCT data)
    {
        uint vk = data.vkCode;
        if (vk == VK_QUIT) { QuitPressed?.Invoke(); Native.PostQuitMessage(0); return true; }
        if (vk == VK_TRIGGER) { TriggerPressed?.Invoke(); return true; }

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

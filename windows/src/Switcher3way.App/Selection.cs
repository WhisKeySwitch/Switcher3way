using System.Runtime.InteropServices;

namespace Switcher3way.App;

/// <summary>
/// Reads the foreground app's selected text via a synthesized Ctrl+C, so the manual trigger can
/// convert a selection instead of the recorded keystroke buffer (macOS parity: the trigger acts on
/// the selection when there is one).
///
/// Detection without destroying the clipboard: remember the clipboard sequence number, send Ctrl+C,
/// and wait briefly for the number to change. No selection → no copy → no change → we report none.
/// The previous clipboard text is put back afterwards, so the user's clipboard survives.
/// </summary>
internal static class Selection
{
    /// <summary>Longest selection we will convert — guards against a "select all" mishap.</summary>
    public const int MaxChars = 200;

    /// <summary>
    /// The current selection, or null when there is none (or it couldn't be read). Restores the
    /// clipboard before returning.
    /// </summary>
    public static string? Read()
    {
        string? saved = ReadClipboardText();
        uint before = GetClipboardSequenceNumber();

        SendCtrlC();

        string? copied = null;
        for (int i = 0; i < 30; i++)             // up to ~300 ms for the app to answer the copy
        {
            Thread.Sleep(10);
            if (GetClipboardSequenceNumber() != before)
            {
                copied = ReadClipboardText();
                break;
            }
        }

        if (saved is not null && copied is not null && copied != saved) WriteClipboardText(saved);
        return string.IsNullOrWhiteSpace(copied) ? null : copied;
    }

    private static void SendCtrlC()
    {
        const ushort VK_CONTROL = 0x11, VK_C = 0x43;
        var inputs = new[]
        {
            Key(VK_CONTROL, 0), Key(VK_C, 0),
            Key(VK_C, Native.KEYEVENTF_KEYUP), Key(VK_CONTROL, Native.KEYEVENTF_KEYUP),
        };
        Native.SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<Native.INPUT>());
    }

    private static Native.INPUT Key(ushort vk, uint flags) => new()
    {
        type = Native.INPUT_KEYBOARD,
        ki = new Native.KEYBDINPUT { wVk = vk, wScan = 0, dwFlags = flags, time = 0, dwExtraInfo = IntPtr.Zero },
    };

    // ---- clipboard ---------------------------------------------------------------------------
    private const uint CF_UNICODETEXT = 13;

    private static string? ReadClipboardText()
    {
        if (!OpenClipboard(IntPtr.Zero)) return null;
        try
        {
            IntPtr h = GetClipboardData(CF_UNICODETEXT);
            if (h == IntPtr.Zero) return null;
            IntPtr p = GlobalLock(h);
            if (p == IntPtr.Zero) return null;
            try { return Marshal.PtrToStringUni(p); }
            finally { GlobalUnlock(h); }
        }
        catch { return null; }
        finally { CloseClipboard(); }
    }

    private static void WriteClipboardText(string text)
    {
        if (!OpenClipboard(IntPtr.Zero)) return;
        try
        {
            EmptyClipboard();
            int bytes = (text.Length + 1) * 2;
            IntPtr mem = GlobalAlloc(GMEM_MOVEABLE, (UIntPtr)bytes);
            if (mem == IntPtr.Zero) return;
            IntPtr p = GlobalLock(mem);
            if (p == IntPtr.Zero) return;
            try { Marshal.Copy((text + '\0').ToCharArray(), 0, p, text.Length + 1); }
            finally { GlobalUnlock(mem); }
            if (SetClipboardData(CF_UNICODETEXT, mem) == IntPtr.Zero) GlobalFree(mem);
        }
        catch { /* best-effort restore */ }
        finally { CloseClipboard(); }
    }

    private const uint GMEM_MOVEABLE = 0x0002;

    [DllImport("user32.dll")] private static extern bool OpenClipboard(IntPtr hWndNewOwner);
    [DllImport("user32.dll")] private static extern bool CloseClipboard();
    [DllImport("user32.dll")] private static extern bool EmptyClipboard();
    [DllImport("user32.dll")] private static extern IntPtr GetClipboardData(uint format);
    [DllImport("user32.dll")] private static extern IntPtr SetClipboardData(uint format, IntPtr hMem);
    [DllImport("user32.dll")] private static extern uint GetClipboardSequenceNumber();
    [DllImport("kernel32.dll")] private static extern IntPtr GlobalAlloc(uint flags, UIntPtr bytes);
    [DllImport("kernel32.dll")] private static extern IntPtr GlobalLock(IntPtr hMem);
    [DllImport("kernel32.dll")] private static extern bool GlobalUnlock(IntPtr hMem);
    [DllImport("kernel32.dll")] private static extern IntPtr GlobalFree(IntPtr hMem);
}

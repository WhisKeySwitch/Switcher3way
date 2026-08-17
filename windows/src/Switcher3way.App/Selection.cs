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
        int waited = 0;
        for (int i = 0; i < 30; i++)             // up to ~300 ms for the app to answer the copy
        {
            Thread.Sleep(10);
            waited = (i + 1) * 10;
            if (GetClipboardSequenceNumber() != before)
            {
                copied = ReadClipboardText();
                break;
            }
        }

        // A changed sequence number is not proof that *our* Ctrl+C copied a selection — anything on the
        // machine can write to the clipboard, and this method then hands back that unrelated text as
        // though the user had selected it. Observed for real: with nothing selected it returned another
        // process's clipboard string, the trigger converted it, and the rewrite typed the result at the
        // caret. Text nobody selected must never become text the app rewrites.
        //
        // So when the content did not change, fall back on the accessibility tree: if it can confirm a
        // selection exists, the identical text is a genuine copy of it (the user had already copied the
        // same words). Only when nothing can confirm a selection is the identical text treated as no copy
        // at all. Comparing content alone declined a real select-all-then-convert, which is a working
        // feature refusing to work.
        if (copied is not null && saved is not null && copied == saved && HasSelection() != true)
        {
            Diagnostics.Log("  selection: clipboard unchanged and no selection confirmed — treating as nothing selected");
            copied = null;
        }

        // "No selection" and "the app was too slow to answer our copy" are indistinguishable from the
        // outside and used to look identical from the inside too — both returned null in silence, and the
        // trigger then reported having nothing to convert. Length only, never the text: this runs before
        // anything knows whether the focused field holds a credential.
        Diagnostics.Log(copied is null
            ? $"  selection: no copy arrived within {waited} ms — treating as nothing selected"
            : $"  selection: read {copied.Length} chars after {waited} ms");

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
        ki = new Native.KEYBDINPUT { wVk = vk, wScan = 0, dwFlags = flags, time = 0, dwExtraInfo = Native.OwnInputTag },
    };

    // ---- "is anything selected?" -------------------------------------------------------------
    // The UIA client is expensive to create and safe to reuse; this runs on every trigger press.
    private static Interop.UIAutomationClient.IUIAutomation? _uia;
    private static bool _uiaBroken;
    private const int UIA_TextPatternId = 10014;

    /// <summary>
    /// Whether the focused element has a non-empty text selection: true / false / <c>null</c> when it
    /// cannot be determined. Costs one UI Automation round trip and, unlike <see cref="Read"/>, has no
    /// side effects — no synthesized Ctrl+C and no clipboard churn.
    ///
    /// This exists to keep a rewrite from erasing text nobody asked it to. A buffer-driven rewrite
    /// erases its own recorded length at the caret with backspaces, and when something is selected the
    /// *first* backspace erases the selection instead — so the rest eat whatever precedes it. Every
    /// gesture that makes a selection now also clears the buffer, which is the real fix; this is the
    /// backstop for the ones that don't announce themselves, touch selection above all.
    /// </summary>
    public static bool? HasSelection()
    {
        if (_uiaBroken) return null;
        try
        {
            _uia ??= new Interop.UIAutomationClient.CUIAutomation();
            var focused = _uia.GetFocusedElement();
            if (focused is null) return null;
            if (focused.GetCurrentPattern(UIA_TextPatternId)
                is not Interop.UIAutomationClient.IUIAutomationTextPattern text) return null;
            var ranges = text.GetSelection();
            if (ranges is null) return null;
            for (int i = 0; i < ranges.Length; i++)
            {
                // Two characters is all it takes to know the range is not just a collapsed caret.
                if (!string.IsNullOrEmpty(ranges.GetElement(i).GetText(2))) return true;
            }
            return false;
        }
        catch (Exception ex)
        {
            // Say so once: the consequence is that the backstop is off, so it must not be silent.
            _uiaBroken = true;
            Diagnostics.LogAlways("selection: UI Automation unavailable, cannot detect selections: " + ex.Message);
            return null;
        }
    }

    /// <summary>
    /// The text immediately to the left of the caret in the focused element, up to
    /// <paramref name="length"/> characters — or <c>null</c> when it cannot be read.
    ///
    /// This is how a rewrite checks its own work. It reads through the UI Automation text pattern, so
    /// unlike <see cref="Read"/> it neither synthesizes keystrokes nor touches the clipboard, and it can
    /// run after every rewrite without the user noticing. Where the target exposes no text pattern the
    /// answer is <c>null</c>, which callers must treat as "unverified" rather than "wrong" — an
    /// unreadable target is not evidence of failure.
    /// </summary>
    public static string? TextBeforeCaret(int length)
    {
        if (_uiaBroken || length <= 0) return null;
        try
        {
            _uia ??= new Interop.UIAutomationClient.CUIAutomation();
            var focused = _uia.GetFocusedElement();
            if (focused is null) return null;
            if (focused.GetCurrentPattern(UIA_TextPatternId)
                is not Interop.UIAutomationClient.IUIAutomationTextPattern text) return null;

            // The caret is a degenerate selection range; walk its start back `length` characters and
            // read what lies between. Cloning first keeps the user's actual selection untouched.
            var ranges = text.GetSelection();
            if (ranges is null || ranges.Length == 0) return null;
            var range = ranges.GetElement(0);
            if (range is null) return null;
            range = range.Clone();
            range.MoveEndpointByRange(Interop.UIAutomationClient.TextPatternRangeEndpoint.TextPatternRangeEndpoint_End,
                                      range, Interop.UIAutomationClient.TextPatternRangeEndpoint.TextPatternRangeEndpoint_Start);
            int moved = range.MoveEndpointByUnit(
                Interop.UIAutomationClient.TextPatternRangeEndpoint.TextPatternRangeEndpoint_Start,
                Interop.UIAutomationClient.TextUnit.TextUnit_Character, -length);
            if (moved == 0) return null;
            return range.GetText(length + 1);
        }
        catch (Exception ex)
        {
            Diagnostics.Log("verify: could not read back the text: " + ex.Message);
            return null;
        }
    }

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

using System.Text;

namespace Switcher3way.App;

/// <summary>
/// Switches the FOREGROUND app's keyboard layout (per-thread on Windows) and confirms the change
/// took effect, falling back to <c>AttachThreadInput</c> + <c>ActivateKeyboardLayout</c>. Graduated
/// from the spike.
/// </summary>
internal static class LayoutSwitcher
{
    public enum SwitchPath { None, Primary, Fallback }

    public readonly record struct ForegroundInfo(IntPtr Hwnd, uint ThreadId, uint ProcessId, string Exe);

    public static ForegroundInfo Foreground()
    {
        IntPtr hwnd = Native.GetForegroundWindow();
        uint tid = Native.GetWindowThreadProcessId(hwnd, out uint pid);
        return new ForegroundInfo(hwnd, tid, pid, ExeName(pid));
    }

    public static string ExeName(uint pid)
    {
        IntPtr h = Native.OpenProcess(Native.PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
        if (h == IntPtr.Zero) return "<unknown>";
        try
        {
            var sb = new StringBuilder(1024);
            uint size = (uint)sb.Capacity;
            return Native.QueryFullProcessImageName(h, 0, sb, ref size)
                ? System.IO.Path.GetFileName(sb.ToString())
                : "<denied>";
        }
        finally { Native.CloseHandle(h); }
    }

    /// <summary>Switch the foreground window to the layout identified by <paramref name="layoutId"/>.</summary>
    public static SwitchPath SwitchForeground(string layoutId)
    {
        if (!Win32LayoutCatalog.TryParseId(layoutId, out var targetHkl)) return SwitchPath.None;

        var fg = Foreground();
        if (fg.Hwnd == IntPtr.Zero) return SwitchPath.None;

        // Primary: post the standard input-language change request to the foreground window.
        Native.PostMessage(fg.Hwnd, Native.WM_INPUTLANGCHANGEREQUEST, Native.INPUTLANGCHANGE_FORWARD, targetHkl);
        if (WaitForHkl(fg.ThreadId, targetHkl)) return SwitchPath.Primary;

        // Fallback: attach to the foreground input thread and activate the layout there.
        uint self = Native.GetCurrentThreadId();
        if (Native.AttachThreadInput(self, fg.ThreadId, true))
        {
            try { Native.ActivateKeyboardLayout(targetHkl, Native.KLF_SETFORPROCESS); }
            finally { Native.AttachThreadInput(self, fg.ThreadId, false); }
            if (WaitForHkl(fg.ThreadId, targetHkl)) return SwitchPath.Fallback;
        }
        return SwitchPath.None;
    }

    private static bool WaitForHkl(uint threadId, IntPtr targetHkl)
    {
        for (int i = 0; i < 20; i++) // ~200ms
        {
            if (Native.GetKeyboardLayout(threadId) == targetHkl) return true;
            Thread.Sleep(10);
        }
        return Native.GetKeyboardLayout(threadId) == targetHkl;
    }
}

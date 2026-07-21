using System.Text;

namespace Switcher3wSpike;

/// <summary>
/// D5/R5: switch the FOREGROUND app's keyboard layout (which is per-thread on Windows) and
/// confirm the change took effect, falling back to a second mechanism if it did not.
/// </summary>
internal static class LayoutSwitcher
{
    public enum Path { None, Primary, Fallback }

    public readonly record struct ForegroundInfo(IntPtr Hwnd, uint ThreadId, uint ProcessId, string Exe);

    public static ForegroundInfo Foreground()
    {
        IntPtr hwnd = Native.GetForegroundWindow();
        uint tid = Native.GetWindowThreadProcessId(hwnd, out uint pid);
        return new ForegroundInfo(hwnd, tid, pid, ExeName(pid));
    }

    /// <summary>Best-effort foreground exe name (D7, used for logging / exclusions later).</summary>
    public static string ExeName(uint pid)
    {
        IntPtr h = Native.OpenProcess(Native.PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
        if (h == IntPtr.Zero) return "<unknown>";
        try
        {
            var sb = new StringBuilder(1024);
            uint size = (uint)sb.Capacity;
            if (Native.QueryFullProcessImageName(h, 0, sb, ref size))
                return System.IO.Path.GetFileName(sb.ToString());
            return "<denied>";
        }
        finally { Native.CloseHandle(h); }
    }

    private static IntPtr ForegroundHkl(uint foregroundThread) => Native.GetKeyboardLayout(foregroundThread);

    /// <summary>
    /// Switch the foreground window to <paramref name="targetHkl"/> and report which mechanism
    /// actually took effect (task 4.1/4.2). Confirmation is by re-reading the foreground thread's
    /// active HKL.
    /// </summary>
    public static Path SwitchForeground(IntPtr targetHkl)
    {
        var fg = Foreground();
        if (fg.Hwnd == IntPtr.Zero) return Path.None;

        // Primary: post the standard input-language change request to the foreground window.
        Native.PostMessage(fg.Hwnd, Native.WM_INPUTLANGCHANGEREQUEST, Native.INPUTLANGCHANGE_FORWARD, targetHkl);
        if (WaitForHkl(fg.ThreadId, targetHkl)) return Path.Primary;

        // Fallback: attach to the foreground input thread and activate the layout there.
        uint self = Native.GetCurrentThreadId();
        if (Native.AttachThreadInput(self, fg.ThreadId, true))
        {
            try
            {
                Native.ActivateKeyboardLayout(targetHkl, Native.KLF_SETFORPROCESS);
            }
            finally
            {
                Native.AttachThreadInput(self, fg.ThreadId, false);
            }
            if (WaitForHkl(fg.ThreadId, targetHkl)) return Path.Fallback;
        }

        return Path.None;
    }

    /// <summary>Poll briefly for the foreground thread's active layout to become the target.</summary>
    private static bool WaitForHkl(uint threadId, IntPtr targetHkl)
    {
        for (int i = 0; i < 20; i++) // ~200ms max
        {
            if (ForegroundHkl(threadId) == targetHkl) return true;
            Thread.Sleep(10);
        }
        return ForegroundHkl(threadId) == targetHkl;
    }
}

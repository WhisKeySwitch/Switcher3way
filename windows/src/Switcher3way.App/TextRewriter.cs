namespace Switcher3way.App;

/// <summary>
/// Erases the mistyped word with synthesized backspaces and inserts the corrected Unicode text via
/// SendInput; detects the elevated-window (UIPI) case by comparing requested vs. injected counts.
/// Graduated from the spike (injected-input is ignored by the hook; injection is per-character).
/// </summary>
internal static class TextRewriter
{
    public enum Result { Ok, Protected, Partial }

    /// <summary>
    /// Replace <paramref name="eraseCount"/> characters with <paramref name="replacement"/>. If a
    /// physical trigger key is held (<paramref name="waitForKeyUpVk"/> != 0), wait for its release
    /// first so it can't interleave with the synthesized stream.
    /// </summary>
    public static Result Rewrite(int eraseCount, string replacement, int waitForKeyUpVk = 0)
    {
        if (waitForKeyUpVk != 0) WaitKeyUp(waitForKeyUpVk, 200);

        int requested = 0, injected = 0;

        for (int i = 0; i < eraseCount; i++)
        {
            requested += 2;
            injected += (int)SendPair(Key((ushort)Native.VK_BACK, '\0', 0),
                                      Key((ushort)Native.VK_BACK, '\0', Native.KEYEVENTF_KEYUP));
        }

        Thread.Sleep(15); // let the erase settle before inserting

        foreach (char c in replacement)
        {
            requested += 2;
            injected += (int)SendPair(Key(0, c, Native.KEYEVENTF_UNICODE),
                                      Key(0, c, Native.KEYEVENTF_UNICODE | Native.KEYEVENTF_KEYUP));
            Thread.Sleep(2);
        }

        if (injected == 0) return Result.Protected;      // fully refused — UIPI against an elevated target
        if (injected < requested) return Result.Partial; // short injection — don't claim success
        return Result.Ok;
    }

    private static uint SendPair(Native.INPUT down, Native.INPUT up)
    {
        var arr = new[] { down, up };
        return Native.SendInput((uint)arr.Length, arr, System.Runtime.InteropServices.Marshal.SizeOf<Native.INPUT>());
    }

    private static void WaitKeyUp(int vk, int maxMs)
    {
        for (int i = 0; i < maxMs / 5; i++)
        {
            if ((Native.GetAsyncKeyState(vk) & 0x8000) == 0) return;
            Thread.Sleep(5);
        }
    }

    private static Native.INPUT Key(ushort vk, char unicode, uint flags) => new()
    {
        type = Native.INPUT_KEYBOARD,
        ki = new Native.KEYBDINPUT { wVk = vk, wScan = unicode, dwFlags = flags, time = 0, dwExtraInfo = IntPtr.Zero },
    };
}

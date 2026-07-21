namespace Switcher3wSpike;

/// <summary>
/// D6/R2: erase a mistyped word with synthesized backspaces and insert the corrected Unicode
/// text via SendInput. Detects the elevated-window (UIPI) case by comparing requested vs.
/// actually-injected event counts, so the spike reports "protected" instead of a silent success.
/// </summary>
internal static class TextRewriter
{
    public enum Result { Ok, Protected, Partial }

    private const int VK_F9 = 0x78;

    /// <summary>
    /// Replace <paramref name="eraseCount"/> characters with <paramref name="replacement"/>.
    /// The trailing boundary char (e.g. the space that finished the word) should already be on
    /// screen and is preserved by the caller — pass only the word's characters.
    /// </summary>
    public static Result Rewrite(int eraseCount, string replacement)
    {
        // Wait for the physical trigger key (F9) to be released so it can't interleave with the
        // synthesized stream (a still-held key was a prime suspect for the "last char repeated" bug).
        WaitKeyUp(VK_F9, 200);

        int requested = 0, injected = 0;

        for (int i = 0; i < eraseCount; i++)
        {
            requested += 2;
            injected += (int)SendPair(Key(Native.VK_BACK, '\0', 0),
                                      Key(Native.VK_BACK, '\0', Native.KEYEVENTF_KEYUP));
        }

        Thread.Sleep(15); // let the erase settle before inserting

        foreach (char c in replacement)
        {
            requested += 2;
            injected += (int)SendPair(Key(0, c, Native.KEYEVENTF_UNICODE),
                                      Key(0, c, Native.KEYEVENTF_UNICODE | Native.KEYEVENTF_KEYUP));
            Thread.Sleep(2); // small gap so rapid identical chars aren't coalesced/autorepeated
        }

        if (injected == 0) return Result.Protected;   // fully refused — UIPI against an elevated target
        if (injected < requested) return Result.Partial; // short injection — don't claim success
        return Result.Ok;
    }

    /// <summary>Send one key-down + key-up as a single SendInput call; returns events injected.</summary>
    private static uint SendPair(Native.INPUT down, Native.INPUT up)
    {
        var arr = new[] { down, up };
        int size = System.Runtime.InteropServices.Marshal.SizeOf<Native.INPUT>();
        return Native.SendInput((uint)arr.Length, arr, size);
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
        ki = new Native.KEYBDINPUT
        {
            wVk = vk,
            wScan = unicode,
            dwFlags = flags,
            time = 0,
            dwExtraInfo = IntPtr.Zero,
        },
    };
}

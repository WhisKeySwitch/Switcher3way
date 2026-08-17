namespace Switcher3way.App;

/// <summary>
/// Erases the mistyped word with synthesized backspaces and inserts the corrected Unicode text via
/// SendInput; detects the elevated-window (UIPI) case by comparing requested vs. injected counts.
/// Graduated from the spike (injected-input is ignored by the hook; injection is per-character).
/// </summary>
internal static class TextRewriter
{
    /// <summary>
    /// <c>Ok</c> means the text on screen was read back and matches what was asked for. It used to mean
    /// only that SendInput accepted the events, which is a different claim entirely — accepted events
    /// can still arrive mangled, and that is how a corrupted rewrite came to report success and then be
    /// used as the input to the next conversion.
    /// <c>Mismatch</c> is a rewrite that landed wrong; <c>Unverified</c> is one that could not be
    /// checked because the target exposes no readable text.
    /// </summary>
    public enum Result { Ok, Protected, Partial, Aborted, Mismatch, Unverified }

    /// <summary>
    /// How fast the synthesized stream is pushed at the target: milliseconds between erase events,
    /// between inserted characters, and the pause separating the two.
    ///
    /// The erase delay is not a guess. Up to and including 0.2.9 there was none — N backspaces went out
    /// back to back — and measurement against Notepad put the failure squarely there: at 46 characters
    /// an unpaced erase corrupted the text in 4 runs out of 4, while 2 ms between backspaces was clean
    /// in 4 out of 4. Neither the settle (15 → 150 ms) nor the character rate (2 → 25 ms) changed
    /// anything, and the threshold sat between 20 and 46 characters — which is why short auto-fixes
    /// never showed it and a long selection cycle showed it every time.
    ///
    /// It is a floor, not a guarantee: at 200 characters even a paced erase can still drop backspaces.
    /// That is what the verification pass exists for.
    /// </summary>
    internal readonly record struct Pace(int EraseMs, int SettleMs, int CharMs)
    {
        public static readonly Pace Default = new(2, 15, 2);

        /// <summary>
        /// Pacing for a rewrite of this size. Short ones — a mistyped word, which is almost every
        /// conversion — keep the 2 ms they have always had, so the common case does not get slower. Long
        /// ones slow down, because that is where the stream outruns the target: a 46-character selection
        /// replaced in one go corrupted even with the erase paced, while the same 46 characters typed
        /// after 46 separate backspaces were fine. The difference is how much work the target was still
        /// doing when the stream arrived.
        /// </summary>
        public static Pace For(int length) => length > 24 ? new(2, 15, 6) : Default;
    }

    /// <summary>
    /// Replace <paramref name="eraseCount"/> characters with <paramref name="replacement"/>. If a
    /// physical trigger key is held (<paramref name="waitForKeyUpVk"/> != 0), wait for its release
    /// first so it can't interleave with the synthesized stream.
    ///
    /// When <paramref name="shouldAbort"/> is supplied and returns true mid-stream (the user typed a
    /// real key), the rewrite stops and restores the text to its pre-rewrite state — the already-erased
    /// characters (the tail of <paramref name="original"/>) are re-inserted and any characters already
    /// typed from <paramref name="replacement"/> are erased — then returns <see cref="Result.Aborted"/>.
    /// This lets a longer multi-word phrase correction never leave the text half-deleted.
    /// </summary>
    /// <param name="pace">
    /// Injection timing. Defaults reproduce the shipping behaviour exactly; `diagrewrite` varies them to
    /// find which one the corruption depends on.
    /// </param>
    public static Result Rewrite(int eraseCount, string replacement, int waitForKeyUpVk = 0,
                                 string? original = null, Func<bool>? shouldAbort = null,
                                 Pace? pace = null)
    {
        var p = pace ?? Pace.For(Math.Max(eraseCount, replacement.Length));
        if (waitForKeyUpVk != 0) WaitKeyUp(waitForKeyUpVk, 200);

        int requested = 0, injected = 0;
        int erased = 0, typed = 0;

        for (int i = 0; i < eraseCount; i++)
        {
            if (shouldAbort?.Invoke() == true) return Restore(original, erased, typed);
            requested += 2;
            injected += (int)SendPair(Key((ushort)Native.VK_BACK, '\0', 0),
                                      Key((ushort)Native.VK_BACK, '\0', Native.KEYEVENTF_KEYUP));
            erased++;
            if (p.EraseMs > 0) Thread.Sleep(p.EraseMs);
        }

        // Settle in proportion to how much text just disappeared, not a flat 15 ms. One backspace that
        // deletes a 46-character selection is a far bigger operation for the target than one that
        // deletes one character, and measurement showed the insert corrupting straight after exactly
        // that: a bulk delete followed too closely by the stream.
        Thread.Sleep(p.SettleMs + Math.Max(eraseCount, replacement.Length));

        foreach (char c in replacement)
        {
            if (shouldAbort?.Invoke() == true) return Restore(original, erased, typed);
            requested += 2;
            injected += (int)SendPair(Key(0, c, Native.KEYEVENTF_UNICODE),
                                      Key(0, c, Native.KEYEVENTF_UNICODE | Native.KEYEVENTF_KEYUP));
            typed++;
            if (p.CharMs > 0) Thread.Sleep(p.CharMs);
        }

        if (injected == 0) return Result.Protected;      // fully refused — UIPI against an elevated target
        if (injected < requested) return Result.Partial; // short injection — don't claim success

        return Verify(replacement, original, erased, typed);
    }

    /// <summary>
    /// Read back what actually landed and compare it with what was asked for.
    ///
    /// Every event being accepted is not evidence that the text arrived: measurement showed a 46-character
    /// rewrite corrupting in every run while reporting success. So success is now something the rewrite
    /// establishes rather than assumes. A mismatch is retried once — the target may simply not have
    /// finished rendering — and then repaired back towards the original, because leaving mangled text in
    /// place is what let one bad rewrite become the input to the next.
    /// </summary>
    private static Result Verify(string replacement, string? original, int erased, int typed)
    {
        if (replacement.Length == 0) return Result.Ok;

        for (int attempt = 0; attempt < 2; attempt++)
        {
            if (attempt > 0) Thread.Sleep(60);          // give the target a moment to catch up
            var landed = Selection.TextBeforeCaret(replacement.Length);
            if (landed is null)
            {
                Diagnostics.Log("  rewrite: unverified — the target exposes no readable text");
                return Result.Unverified;
            }
            if (landed.EndsWith(replacement, StringComparison.Ordinal)) return Result.Ok;
            if (attempt == 0) continue;

            // Log both: which characters differ is what distinguishes a mis-rendered burst from a
            // dropped one, and that difference decided the fix.
            Diagnostics.LogAlways($"  rewrite: MISMATCH — wanted \"{replacement}\", landed \"{landed}\"");
            Repair(original, typed);
            return Result.Mismatch;
        }
        return Result.Ok;
    }

    /// <summary>
    /// Put back the text a completed-but-wrong rewrite replaced: erase what was typed, then re-insert the
    /// whole original. Distinct from <see cref="Restore"/>, which unwinds a rewrite abandoned *mid-erase*
    /// and so only re-inserts the tail it got to.
    ///
    /// Does nothing without the original text. Erasing what we typed and putting nothing back would turn a
    /// mangled word into no word at all — during development this exact path emptied a document, which is
    /// a worse failure than the one being repaired. Leaving the mangled text is the lesser harm, and the
    /// caller reports the mismatch either way.
    /// </summary>
    private static void Repair(string? original, int typed)
    {
        if (original is null)
        {
            Diagnostics.LogAlways("  rewrite: not repairing — no record of what was replaced; leaving the text as it landed");
            return;
        }
        var p = Pace.For(Math.Max(typed, original.Length));
        for (int i = 0; i < typed; i++)
        {
            SendPair(Key((ushort)Native.VK_BACK, '\0', 0),
                     Key((ushort)Native.VK_BACK, '\0', Native.KEYEVENTF_KEYUP));
            Thread.Sleep(p.EraseMs);
        }
        Thread.Sleep(p.SettleMs + Math.Max(typed, original.Length));
        foreach (char c in original)
        {
            SendPair(Key(0, c, Native.KEYEVENTF_UNICODE),
                     Key(0, c, Native.KEYEVENTF_UNICODE | Native.KEYEVENTF_KEYUP));
            Thread.Sleep(p.CharMs);
        }
        Diagnostics.LogAlways($"  rewrite: repaired back to \"{original}\"");
    }

    /// <summary>Undo a partial rewrite: erase the <paramref name="typed"/> chars already inserted, then
    /// re-insert the last <paramref name="erased"/> chars of <paramref name="original"/>.</summary>
    private static Result Restore(string? original, int erased, int typed)
    {
        for (int i = 0; i < typed; i++)
            SendPair(Key((ushort)Native.VK_BACK, '\0', 0),
                     Key((ushort)Native.VK_BACK, '\0', Native.KEYEVENTF_KEYUP));

        if (original is not null && erased > 0)
        {
            var tail = original.Length >= erased ? original[^erased..] : original;
            foreach (char c in tail)
                SendPair(Key(0, c, Native.KEYEVENTF_UNICODE),
                         Key(0, c, Native.KEYEVENTF_UNICODE | Native.KEYEVENTF_KEYUP));
        }
        return Result.Aborted;
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
        ki = new Native.KEYBDINPUT { wVk = vk, wScan = unicode, dwFlags = flags, time = 0, dwExtraInfo = Native.OwnInputTag },
    };
}

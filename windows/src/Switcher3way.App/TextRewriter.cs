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
    /// How the old text is removed. <see cref="EraseMode.PerKey"/> is the only one measured correct, and
    /// the others exist so that stays a finding rather than folklore — reachable through `diagrewrite`.
    /// Measurements are in <c>openspec/changes/archive/…-verify-the-old-text-is-gone/design.md</c>.
    ///
    /// The failure modes differ, and that matters more than the speed. A lost backspace deletes the wrong
    /// amount of text and nothing on screen says so. A lost <c>Shift+Left</c> only makes the selection
    /// shorter, so the replacement covers less than intended and the read-back catches it.
    /// </summary>
    internal enum EraseMode
    {
        /// <summary>One backspace per SendInput call, one pause each. What shipped through 0.3.0.</summary>
        PerKey,
        /// <summary>Several backspaces per call, one pause per batch — fewer pauses, same total events.</summary>
        Batched,
        /// <summary>Per key, but the pause is a spin-wait, so a 2 ms pace really costs 2 ms.</summary>
        Spin,
        /// <summary>No backspaces at all: select the range and let the replacement overwrite it.</summary>
        Select,
    }

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
                                 Pace? pace = null, EraseMode? eraseMode = null, int batch = DefaultBatch)
    {
        var p = pace ?? Pace.For(Math.Max(eraseCount, replacement.Length));
        // A single "erase" that is really "kill the live selection" must stay a plain backspace: the caller
        // passes 1 because the target already has the range selected, so selecting one character to the
        // left instead would replace the wrong thing entirely.
        var mode = eraseMode ?? (eraseCount > 1 ? DefaultEraseMode : EraseMode.PerKey);
        if (waitForKeyUpVk != 0) WaitKeyUp(waitForKeyUpVk, 200);

        // Photograph the screen before touching it. Without this, verification can only ask "did my new
        // text arrive?" — which passes when the new text arrives and the old text is still sitting there,
        // measured for real: a replacement landed after the original instead of over it and was reported
        // as a success. The prefix is read rather than assumed, so a document that legitimately repeats
        // the same word is not mistaken for a failed removal.
        string? before = original is null ? null
                       : Selection.TextBeforeCaret(original.Length + PrefixContext);
        // And how far the caret is from the start, which is what tells "replaced it" from "inserted in
        // front of it" when there is no preceding text to compare — the case that let a failed removal
        // report success.
        int countBefore = original is null ? -1
                        : Selection.CharsBeforeCaret(original.Length + replacement.Length + CountSlack);
        // The trailing side too. A replacement that inserts in front of the old text leaves everything
        // before the caret looking perfect, with the stale copy sitting just past it.
        int tailBefore = original is null ? -1
                       : Selection.CharsAfterCaret(original.Length + replacement.Length + CountSlack);

        int requested = 0, injected = 0;
        int erased = 0, typed = 0;

        var eraseClock = System.Diagnostics.Stopwatch.StartNew();
        if (!Erase(eraseCount, mode, batch, p, shouldAbort, ref requested, ref injected, ref erased))
            return Restore(original, erased, typed);
        eraseClock.Stop();
        // Nominal vs actual, because they are not the same number and the difference is the whole reason
        // a long rewrite felt slow: Thread.Sleep of a few milliseconds is rounded up to the system timer
        // quantum, about 15.6 ms by default. 200 backspaces "paced at 2 ms" therefore cost ~3 s, not 400 ms.
        if (eraseCount > 0)
            Diagnostics.Log($"  rewrite: erased {eraseCount} in {eraseClock.ElapsedMilliseconds} ms " +
                            $"(nominal {eraseCount * p.EraseMs} ms)");

        // Settle in proportion to how much text just disappeared, not a flat 15 ms. One backspace that
        // deletes a 46-character selection is a far bigger operation for the target than one that
        // deletes one character, and measurement showed the insert corrupting straight after exactly
        // that: a bulk delete followed too closely by the stream.
        Thread.Sleep(p.SettleMs + Math.Max(eraseCount, replacement.Length));

        // Long text goes in as one paste rather than hundreds of keystrokes. Per-character injection is
        // what the target mis-renders and what makes a 200-character rewrite take six seconds; a paste is
        // a single chord that cannot be outrun and cannot be half-delivered. Short text keeps the
        // keystroke path: it is already reliable, and it leaves the user's clipboard alone.
        if (replacement.Length > PasteAbove) return PasteAndVerify(replacement, original, before, countBefore, tailBefore, erased);

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

        return Verify(replacement, original, before, countBefore, tailBefore, erased, typed);
    }

    /// <summary>
    /// Above this many characters a replacement is pasted rather than typed. Below it, typing is already
    /// reliable (measured clean at 5, 10 and 20 characters) and costs the user nothing; above it, typing
    /// is both slow and the thing that arrives mangled.
    /// </summary>
    private const int PasteAbove = 24;

    /// <summary>Default strategy and batch size. Both are measured results — see the change's design.</summary>
    private const EraseMode DefaultEraseMode = EraseMode.PerKey;
    private const int DefaultBatch = 8;

    /// <summary>How much text before the replacement is read as context, to tell a failed removal
    /// apart from a document that simply repeats the same word.</summary>
    private const int PrefixContext = 8;

    /// <summary>Headroom on the caret-offset probe, so a normal rewrite never saturates it.</summary>
    private const int CountSlack = 64;

    /// <summary>
    /// Remove <paramref name="count"/> characters ahead of the caret. Returns false if a real keystroke
    /// arrived and the caller should unwind.
    ///
    /// <paramref name="erased"/> counts characters actually gone from the screen, which is why
    /// <see cref="EraseMode.Select"/> leaves it at zero: selecting text removes nothing, so an abort
    /// between the selection and the replacement has nothing to put back.
    /// </summary>
    private static bool Erase(int count, EraseMode mode, int batch, Pace p, Func<bool>? shouldAbort,
                              ref int requested, ref int injected, ref int erased)
    {
        if (count <= 0) return true;

        if (mode == EraseMode.Select)
        {
            // Extend the selection leftwards over the range, then let the insert overwrite it. Caret
            // movement cannot destroy text, so a dropped event costs correctness (a short selection the
            // read-back will catch) rather than the user's characters.
            // Shift is pressed and released in calls of its own, with a gap, and held down across all the
            // arrows in between. Packing Shift-up into the same SendInput batch as the arrows does not
            // work: the asynchronous key state advances the moment the events are queued, so a target that
            // asks for the modifier while processing the arrows sees Shift already released and moves the
            // caret without selecting anything. Measured — the replacement landed at position 0 with the
            // old text untouched after it.
            requested += 2;
            injected += (int)SendPair(Key((ushort)Native.VK_SHIFT, '\0', 0),
                                      Key((ushort)Native.VK_SHIFT, '\0', 0));   // down twice: no release yet
            Wait(p.EraseMs, spin: false);

            for (int sent = 0; sent < count; sent += batch)
            {
                if (shouldAbort?.Invoke() == true)
                {
                    SendPair(Key((ushort)Native.VK_SHIFT, '\0', Native.KEYEVENTF_KEYUP),
                             Key((ushort)Native.VK_SHIFT, '\0', Native.KEYEVENTF_KEYUP));
                    return false;   // nothing removed yet, but never leave Shift stuck down
                }
                int n = Math.Min(batch, count - sent);
                var arr = new Native.INPUT[n * 2];
                for (int i = 0; i < n; i++)
                {
                    arr[i * 2] = Key(VK_LEFT, '\0', 0);
                    arr[i * 2 + 1] = Key(VK_LEFT, '\0', Native.KEYEVENTF_KEYUP);
                }
                requested += arr.Length;
                injected += (int)Native.SendInput((uint)arr.Length, arr,
                                System.Runtime.InteropServices.Marshal.SizeOf<Native.INPUT>());
                Wait(p.EraseMs, spin: false);
            }

            requested += 2;
            injected += (int)SendPair(Key((ushort)Native.VK_SHIFT, '\0', Native.KEYEVENTF_KEYUP),
                                      Key((ushort)Native.VK_SHIFT, '\0', Native.KEYEVENTF_KEYUP));
            Wait(p.EraseMs, spin: false);
            return true;
        }

        int per = mode == EraseMode.Batched ? Math.Max(1, batch) : 1;
        for (int sent = 0; sent < count; sent += per)
        {
            if (shouldAbort?.Invoke() == true) return false;
            int n = Math.Min(per, count - sent);
            var arr = new Native.INPUT[n * 2];
            for (int i = 0; i < n; i++)
            {
                arr[i * 2] = Key((ushort)Native.VK_BACK, '\0', 0);
                arr[i * 2 + 1] = Key((ushort)Native.VK_BACK, '\0', Native.KEYEVENTF_KEYUP);
            }
            requested += arr.Length;
            injected += (int)Native.SendInput((uint)arr.Length, arr,
                            System.Runtime.InteropServices.Marshal.SizeOf<Native.INPUT>());
            erased += n;
            Wait(p.EraseMs, spin: mode == EraseMode.Spin);
        }
        return true;
    }

    private const ushort VK_LEFT = 0x25;

    /// <summary>
    /// Pause for <paramref name="ms"/>. <c>Thread.Sleep</c> of a few milliseconds is rounded up to the
    /// system timer quantum — about 15.6 ms by default — so a "2 ms" pace repeated two hundred times cost
    /// three seconds rather than four hundred milliseconds. <paramref name="spin"/> busies the CPU instead,
    /// which is accurate but not free; which one is worth it is a measured question.
    /// </summary>
    private static void Wait(int ms, bool spin)
    {
        if (ms <= 0) return;
        if (!spin) { Thread.Sleep(ms); return; }
        var sw = System.Diagnostics.Stopwatch.StartNew();
        long target = (long)(ms * (System.Diagnostics.Stopwatch.Frequency / 1000.0));
        while (sw.ElapsedTicks < target) Thread.SpinWait(40);
    }

    /// <summary>
    /// Replace by clipboard: borrow the clipboard, send one Ctrl+V, verify, hand the clipboard back.
    ///
    /// The clipboard is restored only after the paste has been seen on screen — restoring it earlier can
    /// hand the target the old contents before it has processed the chord, which would paste the wrong
    /// text. Verification is what establishes the paste landed, so it doubles as that wait.
    /// </summary>
    private static Result PasteAndVerify(string replacement, string? original, string? before, int countBefore, int tailBefore, int erased)
    {
        var saved = Selection.SwapClipboard(replacement);
        try
        {
            uint injected = SendChord((ushort)Native.VK_CONTROL, (ushort)VK_V);
            if (injected == 0) return Result.Protected;   // UIPI refused it — an elevated target
            return Verify(replacement, original, before, countBefore, tailBefore, erased, replacement.Length);
        }
        finally { Selection.RestoreClipboard(saved); }
    }

    private const ushort VK_V = 0x56;

    /// <summary>Modifier held across one key, as four events in one call.</summary>
    private static uint SendChord(ushort modifier, ushort key)
    {
        var arr = new[]
        {
            Key(modifier, '\0', 0), Key(key, '\0', 0),
            Key(key, '\0', Native.KEYEVENTF_KEYUP), Key(modifier, '\0', Native.KEYEVENTF_KEYUP),
        };
        return Native.SendInput((uint)arr.Length, arr,
                                System.Runtime.InteropServices.Marshal.SizeOf<Native.INPUT>());
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
    private static Result Verify(string replacement, string? original, string? before, int countBefore, int tailBefore, int erased, int typed)
    {
        if (replacement.Length == 0) return Result.Ok;

        // What the screen should read afterwards: whatever preceded the old text, then the new text. This
        // is only available when the "before" photograph actually ended with the text we set out to
        // replace; when it did not, our model of the screen was already wrong and the loose check is all
        // that can honestly be claimed.
        string? wanted = null;
        if (before is not null && original is not null && before.EndsWith(original, StringComparison.Ordinal))
            wanted = before[..(before.Length - original.Length)] + replacement;

        for (int attempt = 0; attempt < 2; attempt++)
        {
            if (attempt > 0) Thread.Sleep(60);          // give the target a moment to catch up
            var landed = Selection.TextBeforeCaret((wanted ?? replacement).Length);
            if (landed is null)
            {
                // Retry rather than give up: Chromium builds its accessibility tree only once a client
                // asks for it, so the first read of a browser text box legitimately returns nothing and
                // the second succeeds. Measured in Edge — first rewrite Unverified, second Ok.
                if (attempt == 0) continue;
                Diagnostics.Log("  rewrite: unverified — the target exposes no readable text");
                return Result.Unverified;
            }

            // How many characters *should* now precede the caret, if the old text went and the new text
            // arrived. A saturated or unavailable count (-1) means this cannot be judged and only the text
            // comparison is left.
            int cap = (original?.Length ?? 0) + replacement.Length + CountSlack;
            int countAfter = countBefore >= 0 && countBefore < cap ? Selection.CharsBeforeCaret(cap) : -1;
            bool countUsable = countBefore >= 0 && countBefore < cap && countAfter >= 0 && countAfter < cap;
            int expected = countBefore - (original?.Length ?? 0) + replacement.Length;

            bool textOk = wanted is not null
                ? landed.EndsWith(wanted, StringComparison.Ordinal)
                : landed.EndsWith(replacement, StringComparison.Ordinal);

            // Nothing should have appeared after the caret. If it grew, the old text is still there on the
            // far side — the failure that looks perfect from behind.
            int tailAfter = tailBefore >= 0 ? Selection.CharsAfterCaret(cap) : -1;
            bool tailUsable = tailBefore >= 0 && tailBefore < cap && tailAfter >= 0 && tailAfter < cap;
            bool tailOk = !tailUsable || tailAfter <= tailBefore;

            if (textOk && (!countUsable || countAfter == expected) && tailOk) return Result.Ok;
            if (attempt == 0) continue;

            // Distinguish the two failures, because they need opposite repairs. If the old text is still
            // sitting immediately before the new text, the insert worked and the removal did not: undoing
            // means deleting what we typed and stopping there. Re-inserting the original as well — which is
            // what the ordinary repair does — would leave the user with two copies of it.
            bool oldTextSurvived = original is not null && original.Length > 0
                                && ((tailUsable && tailAfter > tailBefore)
                                    || (countUsable
                                            ? countAfter == countBefore + replacement.Length
                                            : landed.EndsWith(original + replacement, StringComparison.Ordinal)));
            Diagnostics.LogAlways($"  rewrite: MISMATCH — wanted \"{wanted ?? replacement}\", landed \"{landed}\"" +
                                  (countUsable ? $" [caret {countBefore} -> {countAfter}, expected {expected}]" : "") +
                                  (tailUsable ? $" [trailing {tailBefore} -> {tailAfter}]" : "") +
                                  (oldTextSurvived ? " (the old text was never removed)" : ""));
            if (oldTextSurvived) EraseTyped(typed);
            else Repair(original, typed);
            return Result.Mismatch;
        }
        return Result.Ok;
    }

    /// <summary>
    /// Delete just what this rewrite typed, putting nothing back. For the case where the replacement landed
    /// but the text it was supposed to replace is still there: removing the insert restores exactly the
    /// pre-rewrite screen, and re-inserting the original on top would duplicate it.
    /// </summary>
    private static void EraseTyped(int typed)
    {
        var p = Pace.For(typed);
        for (int i = 0; i < typed; i++)
        {
            SendPair(Key((ushort)Native.VK_BACK, ' ', 0),
                     Key((ushort)Native.VK_BACK, ' ', Native.KEYEVENTF_KEYUP));
            Wait(p.EraseMs, spin: false);
        }
        Diagnostics.LogAlways($"  rewrite: removed the {typed} characters it had inserted; the original text is untouched");
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

        // Put it back the same way it would have gone in. Retyping a long original character by character
        // is both slow and exposed to the very failure being repaired, so a long repair pastes too.
        if (original.Length > PasteAbove)
        {
            var saved = Selection.SwapClipboard(original);
            try { SendChord((ushort)Native.VK_CONTROL, VK_V); }
            finally { Thread.Sleep(40 + original.Length); Selection.RestoreClipboard(saved); }
        }
        else
        {
            foreach (char c in original)
            {
                SendPair(Key(0, c, Native.KEYEVENTF_UNICODE),
                         Key(0, c, Native.KEYEVENTF_UNICODE | Native.KEYEVENTF_KEYUP));
                Thread.Sleep(p.CharMs);
            }
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

# Design — Fix Retype/Typing Race

## Context

Auto-conversion replaces the mis-typed word by injecting synthetic events: N backspaces (3 ms apart), a 20 ms pause, then a Unicode-string insert (`TextConverter.retype`, running on `injectQueue` so the event tap never starves). The whole window is ~50–150 ms. The guard that cancels a conversion when the user types *before the decision* already exists (a letter after the boundary clears `prevWordKeys`, so `handleAutoConvert` bails), but once `beginCycle` has scheduled the injection nothing stops it: real keystrokes flow to the target app directly (listen-only tap), interleave with our backspaces, and get erased. The layout is also switched immediately at scheduling time (`AppDelegate.handleAutoConvert`), so the rest of a fast-typed phrase renders in the new layout even when the replacement itself got mangled.

Relevant fact: the CGEvent tap callback runs on the main run loop, and during injection the main thread is idle (injection is on a background queue) — so real keydowns are observed with millisecond latency while injection is in flight. Synthetic events are already distinguishable: they carry `kSwitcher3wEventMarker` in `eventSourceUserData` and are filtered out before `handleKeyDown` is ever called.

## Goals / Non-Goals

**Goals:**
- A real keystroke (or mouse click / focus change) during injection aborts the remaining injection within one step (~3 ms granularity).
- An abort restores the already-erased characters so no user text is lost.
- Layout switch, `markConverted`, status icon, and `lastAutoConverted` happen only after injection completed successfully.
- The same protection covers every user of the shared retype engine (auto-convert single-step cycle and the manual ⌥ cycle).

**Non-Goals:**
- Holding/replaying user events during injection (would require a consuming event tap; tap-timeout and event-loss risk is not worth it).
- Making conversion of every word succeed for arbitrarily fast typists — precision-first: when in doubt, leave the text alone; the ⌥ trigger remains for missed words.
- Changing the clipboard/selection conversion path (`convertViaClipboard`) — it acts on an explicit trigger over selected text and pauses typing by its nature; out of scope.

## Decisions

1. **Abort signal: a lock-protected flag on `TextConverter`, set synchronously from the event-tap path.**
   `nonisolated private let realInputSinceSchedule = OSAllocatedUnfairLock(initialState: false)` (macOS 13+, no new dependencies). `beginCycle`/`cycleStep` clear it at scheduling time (main thread, before returning); `KeyboardMonitor` sets it via a new `nonisolated func noteRealUserEvent()` called from `handleKeyDown` and `resetBuffersOnClick` (both already receive only marker-filtered real events). *Alternative considered:* reusing the existing `onUserInput` callback — rejected, it dispatches async to main and is gated behind the caret-flag setting; the abort signal must be synchronous and unconditional.

2. **Check the flag before every synthetic event post.** The injection loop checks before each backspace and before the final insert. This bounds the interleave damage to at most one in-flight event (~3 ms window) instead of the whole 50–150 ms injection.

3. **Restore on abort: re-insert the erased suffix.** `retype` gains the actual string being erased (the caller knows it: `home` for `beginCycle`, the current step text for `cycleStep`). If aborted after erasing k of n characters, re-insert the last k characters of that string via the existing `insertText`. Perfect ordering can't be guaranteed if a user char landed exactly inside the 3 ms window, but the failure degrades from "half the phrase destroyed" to "one character transposed" in the worst case, and to "nothing happened" in the typical one.

4. **Completion callback instead of synchronous success.** `beginCycle` and `cycleStep` gain a `completion: @escaping @MainActor (Bool) -> Void` invoked from `injectQueue` (via `Task { @MainActor … }`) — `true` only if all events were posted. `handleAutoConvert` moves `LayoutSwitcher.switchTo`, `keyboardMonitor.markConverted()`, `updateStatusIcon()`, and `lastAutoConverted` into the success branch. The manual-trigger call sites in `AppDelegate` move their layout switch the same way. *Alternative considered:* keep switching the layout eagerly and switch back on abort — rejected: flipping the layout twice under the user's fingers renders a few keystrokes in the wrong layout either way and is harder to reason about.
   *Trade-off accepted:* on success the layout now switches ~50–150 ms after the space instead of instantly. If the user starts the next word inside that window the conversion aborts entirely — see Risks.

5. **Abort must also reset cycle state.** On abort: `isConverting = false`, and the cycle bookkeeping (`cycleSteps`/`cycleIndex`/`lastWasBuffer`) is invalidated so a subsequent ⌥ tap doesn't try to "cycle" text that was never replaced. Log as `cycle abort: user typed (erased k/n, restored)` for the debug log.

## Risks / Trade-offs

- [Fast typists get fewer auto-conversions: any keystroke within ~150 ms after the space cancels the fix] → By design (precision-first). The word stays available to the manual ⌥ trigger; the debug log records each abort so the frequency is observable.
- [A user char can land inside the ~3 ms window between flag check and event post] → Damage bounded to one character near the caret; restore logic still returns the erased text. Cannot be fully eliminated without a consuming tap (explicit non-goal).
- [Restore itself races with continued typing] → The restore insert is a single atomic Unicode event posted at the caret; worst case it lands after one more user char — still strictly better than losing the text. No further retries.
- [Swift 6 strict concurrency: flag is touched from main (set/clear) and injectQueue (read)] → `OSAllocatedUnfairLock` is `Sendable` and `nonisolated`; no `@unchecked` needed.
- [No automated test suite in the repo] → Verification is manual with the debug log (see tasks): fast-typed phrase must abort cleanly; paused typing must convert exactly as before.

## Open Questions

_None — the mechanism is fully determined by the constraints above._

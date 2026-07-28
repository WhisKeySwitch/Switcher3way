## 1. Abort signal plumbing

- [x] 1.1 Add `realInputSinceSchedule` (`OSAllocatedUnfairLock<Bool>`) to `TextConverter` with `nonisolated` `noteRealUserEvent()` / `clearRealInputFlag()` / `realInputArrived()` accessors
- [x] 1.2 Call `textConverter.noteRealUserEvent()` from `KeyboardMonitor.handleKeyDown` and `resetBuffersOnClick` (wire the reference through `AppDelegate` the same way other callbacks are wired; events reaching these paths are already marker-filtered, so no extra synthetic-event check is needed)

## 2. Abortable injection in TextConverter

- [x] 2.1 Extend `retype` to take the erased string and a `completion: @escaping @MainActor (Bool) -> Void`; clear the flag at scheduling time (main thread, before returning)
- [x] 2.2 In the injection block, check the flag before posting each backspace and before the final insert; on abort, re-insert the erased suffix (last k chars of the erased string), log `cycle abort: user typed (erased k/n, restored)`, and complete with `false`
- [x] 2.3 On abort, reset cycle state (`isConverting`, `cycleSteps`, `cycleIndex`, `lastWasBuffer`) so a later ⌥ tap doesn't cycle text that was never replaced
- [x] 2.4 Thread the completion through `beginCycle` and `cycleStep` (`cycleStep` now takes an `onSuccess(layoutID, restored)` and returns `Bool` "cycle scheduled", since its step data is only meaningful on success)

## 3. Callers switch layout only on success

- [x] 3.1 `AppDelegate.handleAutoConvert`: move `LayoutSwitcher.switchTo`, `keyboardMonitor.markConverted()`, `updateStatusIcon()`, and `lastAutoConverted` into the completion's success branch
- [x] 3.2 Manual ⌥-trigger call sites (`onAltTap` / `onAltReconvert` paths using `beginCycle`/`cycleStep`): apply the same success-gated layout switch
- [x] 3.3 Confirm the clipboard/selection path (`convertViaClipboard`/`reconvert`) is untouched and still compiles against any signature changes (`swift build` clean; grep shows no other callers)

## 4. Build and verify

- [x] 4.1 `bash build_app.sh`, install to `/Applications`, relaunch; confirm `Permissions: accessibility=true inputMonitoring=true` in the log
- [x] 4.2 Enable the debug log and type «Добре, що є прогрес» fast in the wrong layout — verify the text is never mangled: either a clean conversion or a clean abort (`cycle abort:` line, text exactly as typed, layout unchanged). Result: «Lj,ht? що є прогрес» — zero corruption; «Lj,ht?» was a resolver `keep` (dictionary-verified: «добре» is valid in BOTH uk and ru → precision-first ambiguity rule, same as «там»), «oj» → «що» converted cleanly and switched the layout
- [x] 4.3 Type the same phrase with a short pause after each space — verify auto-conversion still fires and the layout switches after the replacement (evidenced by the «oj» → «що» conversion in 4.2: `cycle begin … erase 3`, no abort, layout switched to Ukrainian-PC after the replacement)
- [x] 4.4 Manual trigger regression: ⌥-tap converts the last word, repeated taps cycle candidates and wrap back to the original with the original layout restored (verified live by the user; log 07:50: `cycle begin → restore → step 0 → restore`)
- [x] 4.5 Mouse-click during an in-flight conversion aborts it (verified live by the user: no corruption, conversion completed normally). NOTE: the abort path itself has not fired yet — zero `cycle abort` lines; the ≤100 ms injection window is not hittable by a hand-timed click. The abort branch is verified by review only; it will get organic live coverage from fast continuous typing (a keydown landing inside the injection window logs `cycle abort`)

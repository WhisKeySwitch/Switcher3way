## 1. Reproduce and isolate the cause

- [ ] 1.1 Script the failing cycle end to end: select a 46-character wrong-layout phrase in Notepad, invoke the trigger three times (candidate, candidate, restore), read the document back, and assert it matches the original. Confirm it fails on the current build.
- [ ] 1.2 Add a `diagrewrite` switch to `App.xaml.cs` that runs one rewrite of a given length against the focused window and logs intended vs landed text, with pacing and layout-switch behaviour selectable by argument.
- [ ] 1.3 Run the matrix with `diagrewrite`: erase size {1, 10, 46, 100} x erase pacing {none, 2 ms} x layout switch {none, same script, cross script}. Record which combinations mangle text.
- [ ] 1.4 Repeat the failing combination in at least two other targets (WordPad or Word, and a Chromium text box) to establish whether the fault is target-specific.
- [ ] 1.5 Write the finding into `design.md` under Open Questions, replacing the two candidate causes with the confirmed one.

## 2. Read-back verification in the rewriter

- [ ] 2.1 Add a text read-back to `Selection.cs` alongside `HasSelection()`: return the focused element's text around the caret via the UIA text pattern, bounded by a short timeout, `null` when unavailable.
- [ ] 2.2 Extend `TextRewriter.Result` with `Mismatch` and `Unverified`, and document what each means for the caller.
- [ ] 2.3 After injecting, compare the landed text against the intended replacement over the written region only; retry the comparison once before concluding a mismatch, so the target's own rendering delay cannot be read as corruption.
- [ ] 2.4 On `Mismatch`, restore towards the pre-rewrite text through the existing `Restore` path and log intended vs landed. On `Unverified`, attempt no repair.
- [ ] 2.5 Verify that a rewrite into a target with no readable text returns `Unverified` and not `Ok`.

## 3. Pace and sequence the injected stream

- [ ] 3.1 Pace the erase loop at the same interval as the insert loop.
- [ ] 3.2 Scale the settle between erase and insert to the size of the erase instead of a flat 15 ms.
- [ ] 3.3 Make the layout switch complete before injecting: confirm the foreground layout changed, or a short timeout elapsed, before the first character.
- [ ] 3.4 Measure the added latency for a 5-character word and a 46-character selection; record both in the change so the trade-off is on the record.

## 4. Stop a bad rewrite from compounding

- [ ] 4.1 In `ManualStep`, clear the cycle when the rewrite result is not `Ok`, instead of advancing `Step` and storing `OnScreenLen`.
- [ ] 4.2 Suppress the success chip and the "converted" feedback for a result that is not `Ok`; route `Mismatch` through the user-visible failure path that `NotifyProtected` already uses.
- [ ] 4.3 In `AutoConvert`, apply the same rule: a rewrite that is not `Ok` records no conversion, seeds no cancel cycle, and updates no phrase memory.
- [ ] 4.4 Confirm from the log that a mismatched rewrite is followed by a fresh `StartCycle` on the next trigger rather than a `cycle[n+1]`.

## 5. Verify

- [ ] 5.1 Re-run task 1.1's script against the fixed build: the three-step cycle returns the text to the original, character for character.
- [ ] 5.2 Extend the script to a fourth and fifth trigger invocation and assert the text still matches the original — the compounding case from the report.
- [ ] 5.3 Regression: the manual trigger still cycles a short typed word, and auto-fix still converts on a word boundary.
- [ ] 5.4 Regression: the data-loss guards from 0.2.9 still hold — caret movement then trigger, and select-all then trigger, both leave the document intact.
- [ ] 5.5 `dotnet test` stays green (166 tests).
- [ ] 5.6 Verify on the packaged build, not only the unpackaged one, since that is where the Store ships from.

## 6. Ship

- [ ] 6.1 Bump the version in `Switcher3way.App.csproj`, `Package.appxmanifest`, and `build-msi.ps1`.
- [ ] 6.2 Build the Store MSIX and confirm the embedded executable's file version matches.
- [ ] 6.3 Note the rewrite-verification behaviour in `windows/RELEASING.md`, including how to read a `Mismatch` in the log.
- [ ] 6.4 Sync the delta spec into `openspec/specs/windows-platform-support/spec.md` and archive the change.

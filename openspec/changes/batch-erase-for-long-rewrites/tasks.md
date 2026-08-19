## 1. Measure what the erase actually costs

- [ ] 1.1 Record the current baseline with `diagrewrite` at 5, 46, 100 and 200 characters, taking the duration from the app's own log timestamps (`intended=` to `result=`) so harness overhead is excluded. Note it in `design.md`.
- [ ] 1.2 Instrument the erase loop temporarily to log its own elapsed time, and confirm the ~15 ms quantum directly: 200 pauses of a nominal 2 ms should measure ~3 s, not ~400 ms.
- [ ] 1.3 Add an erase-strategy argument to `diagrewrite` alongside the existing pacing numbers: `perkey` (current), `batched:<k>`, `spin`, `select`.

## 2. Try the candidates

- [ ] 2.1 Implement `batched:<k>` — *k* backspaces per `SendInput` array, one pause per batch.
- [ ] 2.2 Implement `spin` — a spin-wait for sub-quantum delays so a 2 ms pause costs 2 ms rather than a timer tick.
- [ ] 2.3 Implement `select` — remove the range by sending *n* `Shift+Left` events and letting the paste replace the selection, with no backspaces at all.
- [ ] 2.4 Run the matrix over {perkey, batched:4, batched:8, batched:16, spin, select} x {46, 100, 200} characters, repeated at least 3 times per cell, recording correctness *and* duration.
- [ ] 2.5 Run the design's open question as its own cells: unpaced erase combined with the paste insert, at 46 and 200 characters, repeated enough times to trust a silent failure's absence.
- [ ] 2.6 Write the results into `design.md` and name the winner, with the failure-mode reasoning explicit where speed and safety disagree.

## 3. Adopt the winner

- [ ] 3.1 Make the chosen strategy the default above the paste threshold; leave the short-word path exactly as it is.
- [ ] 3.2 If `select` wins, confirm it behaves in at least two other targets (a Chromium text box and one more) before adopting, especially across a wrapped line.
- [ ] 3.3 Correct the comment where the pause is configured: a bare `Thread.Sleep` of a few milliseconds is quantised to ~15 ms on Windows, which is why the old numbers did not mean what they said.
- [ ] 3.4 Keep the previous strategy reachable through `diagrewrite` so a regression can be A/B'd without a rebuild.

## 4. Verify

- [ ] 4.1 Latency: 200 characters under ~1.5 s, 46 characters no worse than today's 862 ms, 5 characters still ~234 ms — from the app's log, same rig, same method as the baseline.
- [ ] 4.2 Correctness: the trigger-cycle script passes 5 runs out of 5 with zero mismatches, as it does today.
- [ ] 4.3 Regression: the 0.2.9 data-loss guards still hold — caret movement then trigger, and select-all then trigger, both leave the document intact.
- [ ] 4.4 Regression: auto-fix still converts on a word boundary, and a short word still cycles.
- [ ] 4.5 Clipboard: a long replacement still returns the clipboard, a short one still never touches it.
- [ ] 4.6 `dotnet test` stays green (166 tests).
- [ ] 4.7 Verify on the packaged build, not only the unpackaged one.

## 5. Ship

- [ ] 5.1 Bump the version in `Switcher3way.App.csproj`, `Package.appxmanifest` and `build-msi.ps1`.
- [ ] 5.2 Build both packages and confirm the embedded executable's file version.
- [ ] 5.3 Update `windows/release-notes.md` and the Store "what's new" in en/uk/ru; the user-visible claim is speed, so quote the before and after numbers.
- [ ] 5.4 Publish the release, check the checksum is the only 64-hex string in the notes, and confirm `/releases/latest` still resolves to the macOS DMG.
- [ ] 5.5 Sync the delta spec into `openspec/specs/windows-platform-support/spec.md` and archive the change.

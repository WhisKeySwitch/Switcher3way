## 1. Measure the erase, and settle whether it can be faster

- [x] 1.1 Baseline with `diagrewrite` at 5, 46, 100 and 200 characters, timed from the app's own log.
- [x] 1.2 Instrument the erase loop to prove the ~15 ms quantum directly rather than by inference.
- [x] 1.3 Add an erase-strategy argument to `diagrewrite`: `perkey`, `batched:<k>`, `spin`, `select:<k>`.
- [x] 1.4 Implement and measure all four, one fresh target per cell, taking the app's verdict rather than the harness's diff.
- [x] 1.5 Record the negative result: per-key pacing is the only correct strategy, batching and accurate short pauses both lose events, and the delay is a property of the target. Keep the rejected strategies reachable behind `diagrewrite`.
- [x] 1.6 Retract the latency promise the change proposed before measuring, rather than shipping a spec the code cannot satisfy.

## 2. Close the verification hole the attempt exposed

- [x] 2.1 Add `Selection.CharsBeforeCaret` and `CharsAfterCaret`: counts, capped, without reading the document.
- [x] 2.2 Capture the screen before the rewrite — text and both counts — and pass it through to verification.
- [x] 2.3 Verify the removal as well as the insertion, judging by position so repeated words and empty prefixes are handled.
- [x] 2.4 Split the repair: erase-and-restore when the replacement landed wrong, erase-only when it landed beside the original.
- [x] 2.5 Fix the read-back anchor — the range start is wrong while a selection is live, which made every pre-rewrite figure short by the selection's length.
- [x] 2.6 Have `diagrewrite` pass the text being replaced, or the strict check silently degrades to the loose one.

## 3. Verify

- [x] 3.1 The exposed failure is now caught: a replacement that lands beside the original reports `Mismatch` and names the reason.
- [x] 3.2 The other failure is caught too: a removal that under-deletes reports `Mismatch` with the caret figures.
- [x] 3.3 No false positives: the trigger cycle passes 5 runs out of 5 with zero mismatches, as it did before this change.
- [x] 3.4 The repair restores the pre-rewrite screen exactly, without duplicating the original.
- [x] 3.5 Regressions: the 0.2.9 data-loss guards hold, a short word still cycles, auto-fix still converts.
- [x] 3.6 Latency unchanged within noise, recorded in the design.
- [x] 3.7 `dotnet test` green (166 tests).
- [x] 3.8 Verify on the packaged build, not only the unpackaged one.

## 4. Ship

- [ ] 4.1 Bump the version in `Switcher3way.App.csproj`, `Package.appxmanifest` and `build-msi.ps1`.
- [ ] 4.2 Build both packages and confirm the embedded executable's file version.
- [ ] 4.3 Release notes and Store "what's new" in en/uk/ru — the user-visible claim is that a failed conversion is now undone rather than reported as done.
- [ ] 4.4 Publish, checking the checksum is the only 64-hex string in the notes and that `/releases/latest` still resolves to the macOS DMG.
- [ ] 4.5 Note the `trailing`/`caret` figures in `RELEASING.md` alongside the existing `Mismatch` guidance.
- [ ] 4.6 Sync the delta spec into the main spec and archive the change.

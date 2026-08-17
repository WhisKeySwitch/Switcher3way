## Why

The Windows rewrite engine can land text that differs from what it was asked to type, and report
success anyway. Cycling a 46-character selection through its layouts on 0.2.9 restored
`yyys ffffflwznbq vbyfkj? z gfc zuyznf pf ctkjv` in place of
`vtys nhbyflwznbq vbyfkj? z gfc zuyznf pf ctkjv` — the first two words mangled, the rest exact — while
the log recorded `Ok`. Nobody typed during the rewrite.

Two things make this worse than a cosmetic glitch. The damage compounds: the next trigger reads the
corrupted text and faithfully converts *that*, so each invocation buries the original further. And
`Result.Ok` is currently only a statement that `SendInput` accepted the events — the app never checks
what actually arrived, so it cannot tell a completed rewrite from a corrupted one. For a tool whose
entire job is rewriting text the user has already typed, silent corruption is the most expensive
failure available, and the one the user is least able to recover from.

## What Changes

- Establish what actually causes the mangling, by isolating the two candidates independently rather
  than fixing both blind: the erase burst (N backspaces injected with no delay, then a 15 ms settle
  before 2 ms-paced character injection, so the target is still draining backspaces when characters
  begin arriving) and the layout switch that immediately precedes the insert (the corrupting step is
  the only one whose switch crosses Cyrillic → Latin).
- Pace and sequence the injected stream so the target application can keep up: delay between erase
  events as well as between characters, scale the settle to the size of the erase, and complete the
  layout switch before injecting rather than racing it.
- **Verify the rewrite instead of assuming it.** After injecting, read back what landed and compare it
  with what was intended. A mismatch is reported as a failure, not as `Ok`, and the text is repaired
  to its pre-rewrite state where possible.
- Refuse to cycle from text the engine cannot vouch for, so a corrupted rewrite cannot be used as the
  input to the next conversion and compound.
- Make the failure observable: log the intended text alongside what landed, so a future report of
  "it ruined my text" is diagnosable from one line instead of by inference.

## Capabilities

### New Capabilities

None. This corrects behaviour that the existing rewrite requirement already promises.

### Modified Capabilities

- `windows-platform-support`: the "Rewrite typed text in place" requirement gains verification
  semantics — a rewrite may only be reported as successful when the text that landed matches the text
  intended, and a rewrite whose result cannot be vouched for must not seed a further conversion. The
  requirement currently constrains only what the app *injects* and how it aborts on concurrent typing,
  which is why an injection that was accepted but arrived mangled counts as success today.

## Impact

- `windows/src/Switcher3way.App/TextRewriter.cs` — pacing, settle, layout-switch ordering, read-back
  verification, and a `Result` that distinguishes "injected" from "verified".
- `windows/src/Switcher3way.App/Engine.cs` — `ManualStep` and `AutoConvert` handle an unverified
  rewrite: no chip claiming success, no cycle seeded from unverified text, and the existing
  `NotifyProtected` path extended to cover a corrupted rewrite.
- `windows/src/Switcher3way.App/Selection.cs` — the read-back needs to read on-screen text; the
  existing UIA text-pattern plumbing added for `HasSelection()` is the natural place.
- No change to the detection core (`Switcher3way.Core`), so its 166 tests stand as a regression guard
  for everything upstream of the rewrite.
- Verification is by scripted end-to-end repro against a real build: injected input has been visible
  to the hook since 0.2.7, so the failing cycle can be driven and asserted rather than described.

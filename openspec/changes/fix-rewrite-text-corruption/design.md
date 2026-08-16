## Context

`TextRewriter.Rewrite` is the only place in the Windows build that changes the user's text. It erases
`eraseCount` characters with synthesized backspaces, sleeps 15 ms, then injects the replacement one
character at a time (`KEYEVENTF_UNICODE`, 2 ms apart), and returns `Ok` when `injected == requested`.
`injected` is `SendInput`'s return value: the number of events *accepted into the input queue*. It says
nothing about what the target application did with them.

Observed on 0.2.9, cycling a 46-character selection in Notepad (`RichEditD2DPT`):

```
cycle[0] -> [uk]          "мені тринадцятий минало, я пас ягнята за селом"   Ok   (erase 1)
cycle[1] -> [ru]          "мены тринадцятий минало, я пас ягнята за селом"   Ok   (erase 46, uk→ru)
cycle[2] -> [original:en] "vtys nhbyflwznbq vbyfkj? z gfc zuyznf pf ctkjv"   Ok   (erase 46, ru→en)
...next trigger reads:    "yyys ffffflwznbq vbyfkj? z gfc zuyznf pf ctkjv"
```

The log shows no typing between the restore and the read — only a mouse click to re-select — so step 2
landed the mangled text itself. The signature is narrow and repeatable-looking: only the first ~10
characters are wrong, total length is preserved, and each wrong run holds the run's *last* character
(`vty` → `yyy`, `nhbyf` → `fffff`). Everything from character 10 onward is exact.

Two candidate causes fit, and they are separable:

1. **Injection rate.** The erase loop has no delay at all — 46 backspaces is 92 events pushed back to
   back — followed by only 15 ms before characters start arriving 2 ms apart. A target still draining
   the backspace burst can coalesce the earliest character packets. This fits "only the first N
   characters" and fits step 0 being clean (a selection erases with one backspace).
2. **The layout switch.** Step 2 is the only step whose `LayoutSwitcher.SwitchForeground` crosses
   scripts (Cyrillic → Latin) immediately before injecting. Step 1 also erased 46 characters and landed
   correctly, which is evidence *against* rate being the whole story.

Because step 1 survived the same erase size, this design does not assume cause 1. It isolates first.

## Goals / Non-Goals

**Goals:**

- Establish which of the two candidates actually produces the mangling, with evidence, before changing
  the injection strategy.
- Make a rewrite that lands wrong report itself as wrong, whatever the cause.
- Stop a bad rewrite from becoming the input to the next one, which is what turns one glitch into
  progressive destruction of the user's text.
- Keep the common case — a short word, erase and retype — as fast as it is today.

**Non-Goals:**

- Rewriting the injection mechanism (no move to `WM_CHAR`, `SendMessage`, UIA `SetValue`, or clipboard
  paste as the primary path). Synthesized input is what makes the app work in arbitrary applications;
  changing it is a much larger change with its own failure modes.
- Guaranteeing verification in every application. Some targets expose no readable text; the honest
  outcome there is "unverified", not a promise.
- Touching `Switcher3way.Core`. The detection is not implicated, and its 166 tests stay a fixed point.
- The macOS build. Its rewrite path is separate and has not shown this failure.

## Decisions

### Isolate the cause before treating it

Add a diagnostic switch (`Switcher3way.exe diagrewrite`) that performs a rewrite of a given size
against the focused window and reports intended vs landed text, with pacing and layout-switch
behaviour selectable. Run the matrix: erase size {1, 10, 46, 100} × pacing {current, paced erase} ×
layout switch {none, same script, cross script, completed-before-insert}.

Alternatives considered: fixing both suspects at once. Rejected — it would ship two behavioural changes
of unknown value, and if the real cause were a third thing (target-specific packet handling) we would
believe it fixed while it waited for a different application. The evidence for cause 1 is already
partly contradicted by step 1 landing correctly; that contradiction deserves resolution, not
overwriting.

### Verification is the primary fix, pacing is secondary

Whatever the mechanism, the engine must be able to tell that a rewrite did not land. After injecting,
read the text back and compare against the intended string:

- Read via the UIA text pattern on the focused element — the plumbing added for `Selection.HasSelection()`
  already reaches it, and unlike a clipboard probe it has no side effects on the user's clipboard.
- Compare only the region the rewrite claims to have written.
- On mismatch: return a new `Result.Mismatch`, restore towards the pre-rewrite text using the existing
  `Restore` path, and log intended vs landed.
- Where no readable text is available: return `Result.Unverified`. Callers treat it as "do not claim
  success, do not seed a cycle" but do not attempt a repair, since a blind repair could destroy more
  than it fixes.

Alternatives considered: verifying with the clipboard (Ctrl+C round trip). Rejected — it churns the
user's clipboard on every conversion, costs up to 300 ms, and `Selection.Read` already shows how
fragile clipboard-change detection is. Also considered: no verification, pacing only. Rejected — that
is the current design philosophy, and it is precisely why a corrupting rewrite reported `Ok`.

### Pace and sequence the injected stream

Independent of the cause, the erase loop's total absence of delay is indefensible next to the insert
loop's 2 ms. Give the erase the same pacing, and scale the settle between erase and insert to the size
of the erase rather than a flat 15 ms. Complete the layout switch before injecting: confirm the
foreground layout has actually changed (or a short timeout has elapsed) instead of posting the request
and immediately typing.

The cost is latency on long rewrites — a 46-character selection gains roughly 92 ms of pacing. That is
acceptable for an explicit trigger on a selection; it is the correctness of a rewrite of the user's
text, and the common case (a word of 5–10 characters) gains ~20 ms.

### A failed or unverified step ends the cycle

`ManualStep` currently advances `Step` and stores `OnScreenLen = text.Length` regardless of the result.
When the result is not `Ok`, the cycle is cleared instead: the next trigger invocation starts afresh
from what is on screen. This is what breaks the compounding, and it holds even if a future rewrite
fails for an entirely different reason.

## Risks / Trade-offs

- **UIA read-back is not universally available** → treat it as unverified rather than failed; the
  compounding guard still applies, so the worst case reverts to today's behaviour minus the false claim
  of success.
- **Read-back could be slow in some applications and add latency to every conversion** → bound it with
  a short timeout like the password guard's 0.05 s, and verify only rewrites above a length threshold
  if measurement shows the short ones cost more than they protect.
- **Read-back races the target's own rendering**, so a correct rewrite could read as mismatched and be
  "repaired" into damage → compare after the same settle used before insertion, retry once on
  mismatch before concluding, and never repair on an `Unverified` result.
- **Pacing makes long rewrites visibly slower** → accepted, and bounded by the existing 200-character
  selection cap.
- **The isolation step may show a target-specific cause** we cannot fix by pacing at all (Notepad's
  async RichEdit) → the verification layer still contains the damage, and the finding narrows the
  advice we give rather than being wasted.

## Migration Plan

No data or settings migration. Ships as a normal version bump to both channels; the Store build and the
MSI build share the rewrite path. The verification layer is additive, so a rollback is reverting the
commit.

## Open Questions

- Which of the two candidates is the cause — resolved by the isolation task, and the answer decides
  whether the layout-switch sequencing change is required or merely tidy.
- Does the mangling reproduce in applications other than Notepad? If it is specific to
  `RichEditD2DPT`, the pacing fix may be unnecessary and verification alone is the answer.
- Should auto-fix verify too, or only the manual cycle? Auto-fix rewrites are short and have not been
  reported to corrupt, but the same code path serves both, so the default is to verify both and
  measure the cost.

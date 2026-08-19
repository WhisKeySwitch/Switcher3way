## Why

A rewrite could report success while leaving the text it was supposed to replace sitting on screen.

This change began as a latency fix — a 200-character replacement took 3.4 seconds, and the erase pacing
looked like an accident of `Thread.Sleep` rounding rather than a requirement. Measurement killed that
premise: the ~15 ms the code accidentally waits is exactly what the target needs, and every route to a
faster erase lost events. That result is recorded and the speed-up is abandoned.

What the attempt turned up instead is worth more. Trying to remove text by selecting it rather than
erasing it produced a replacement that landed *beside* the original instead of over it — and the app
reported `Ok`. Verification compares only the text it wrote, so a replacement that arrives correctly next
to text that should have vanished passes. That is the same shape as every defect this codebase has chased:
a surface reporting success for something it never established.

It is not specific to that experiment. Any under-removal — a dropped backspace at the tail, a target that
swallows one — leaves the right replacement adjacent to the wrong leftovers, and today's check waves it
through. The verification added in 0.3.0 closed the "did my text arrive" hole and left the "did the old
text leave" hole open.

## What Changes

- Verify that the replaced text is **gone**, not only that the replacement arrived.
- Judge it by **position, not just content**: measure how far the caret sits from the start and the end of
  the text before and after the rewrite. Content comparison alone cannot tell "replaced the word" from
  "inserted in front of the word" when the document contains nothing else, and cannot tell either from a
  document that legitimately repeats the same word twice.
- Distinguish the two failures, because they need opposite repairs. A replacement that landed *wrong* is
  undone by erasing it and putting the original back. A replacement that landed *beside* the original is
  undone by erasing only what was inserted — putting the original back as well would leave two copies.
- Retract a latency promise this change originally proposed and could not keep, rather than shipping a
  specification the code does not satisfy.
- Keep the measured-and-rejected erase strategies reachable behind `diagrewrite`, so "per-key pacing is
  the only correct one" stays a finding that can be re-tested rather than folklore.

## Capabilities

### New Capabilities

None. This closes a hole in a verification requirement that already exists.

### Modified Capabilities

- `windows-platform-support`: the "Rewrite typed text in place" requirement says a replacement must be
  compared against what was intended, which the implementation satisfied for the inserted text only. It
  needs to require that the removal is verified too, to say that leaving the old text behind is a failure
  with its own repair, and to describe the injection rate as a measured property of the target rather than
  a latency target this project can promise.

## Impact

- `windows/src/Switcher3way.App/Selection.cs` — two new probes that count characters before and after the
  caret without reading the document, plus a correction: the existing read-back anchored at the *start* of
  the current range, which is wrong while a selection is live and made every pre-rewrite measurement short
  by the length of the selection.
- `windows/src/Switcher3way.App/TextRewriter.cs` — capture the screen before the rewrite, compare after,
  and split the repair into its two cases. Also the erase-strategy plumbing from the abandoned speed-up.
- `windows/src/Switcher3way.App/App.xaml.cs` — `diagrewrite` gains the erase strategy and now passes the
  text being replaced, without which the strict check silently degrades to the loose one.
- No change to `Switcher3way.Core`; its 166 tests stay a fixed point.
- Verified with `diagrewrite` for single rewrites and the trigger-cycle script end to end, on both the
  unpackaged and packaged builds.

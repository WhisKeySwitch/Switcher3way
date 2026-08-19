## Why

Replacing a 200-character selection takes **3.4 seconds**. That is long enough to read as a hang, and
long enough that a user will start typing into the middle of it — which aborts the rewrite and leaves
them worse off than if they had never pressed the trigger.

0.3.0 halved the cost by pasting long replacements instead of typing them, so the insert is now a single
event. What remains is the *erase*: 200 backspaces, each followed by a 2 ms pace. The pace is not
optional — an unpaced erase corrupted the text in 4 runs out of 4 at 46 characters, while 2 ms was clean
in 4 out of 4 — but the arithmetic does not explain 3.4 seconds, and the reason it does not is the point
of this change:

**`Thread.Sleep(2)` does not sleep 2 ms.** Windows' default timer granularity rounds it to roughly
15 ms, so 200 paced backspaces cost about 3 seconds of wall clock rather than the 400 ms the code reads
as. The same rounding explains an earlier measurement that made no sense at the time — erase pacing of
5 ms and 10 ms behaved no better than 2 ms, and only 20 ms looked clean — because every one of those
values was landing on the same quantum. The sweep was not measuring what it appeared to measure.

So the latency is an accident of how the pause is implemented, not a price the correctness demanded. It
is worth removing, and cheap to remove, but it cannot be removed blind: the pacing exists because the
target could not keep up, and anything that speeds the stream up risks the corruption it was added to
prevent.

## What Changes

- Establish what the erase actually costs and what it actually needs, separating the two things the
  current code conflates: the *number of events* and the *number of sleeps*.
- Reduce the erase's wall-clock cost for long replacements by one of — decided by measurement, not
  preference:
  - **batching**: several backspaces per `SendInput` call and one pause per batch, cutting sleeps by the
    batch factor;
  - **a real short pause**: a spin-wait or raised timer resolution, so 2 ms means 2 ms;
  - **not erasing at all**: select the range to be replaced with caret-movement events and let the paste
    replace the selection, which removes the backspace stream entirely.
- Prefer the option whose *failure mode* is safest, not merely the fastest. Dropped backspaces delete the
  wrong amount of text silently; dropped caret movements only produce a shorter selection, which the paste
  then replaces and the existing verification catches. Speed and safety may not point the same way, and
  where they conflict this change takes safety.
- Leave short replacements exactly as they are. They are already 234 ms and typed rather than pasted,
  which keeps the clipboard untouched for nearly every conversion the app performs.
- Record the measured latency at 5, 46 and 200 characters before and after, so the claim is a number
  rather than an impression.

## Capabilities

### New Capabilities

None. This makes an existing requirement's promise — injecting "at a rate the target application can
consume" — cost what it should rather than fifteen times that.

### Modified Capabilities

- `windows-platform-support`: the "Rewrite typed text in place" requirement is written in terms of
  *erasing characters*, which presumes the backspace stream. It needs to permit replacing a range by
  selecting it, and to say what the user is entitled to expect about how long a replacement takes — a
  correctness guarantee that takes several seconds to deliver is not the same feature as one that
  arrives promptly.

## Impact

- `windows/src/Switcher3way.App/TextRewriter.cs` — the erase loop, the `Pace` record, and possibly a new
  erase strategy alongside it.
- `windows/src/Switcher3way.App/App.xaml.cs` — `diagrewrite` gains a way to select the erase strategy, as
  it already does for pacing, so the matrix can compare them.
- No change to the verification layer, which is what makes this safe to experiment with: a strategy that
  loses events is reported as a `Mismatch` and repaired rather than silently shipping corruption.
- No change to `Switcher3way.Core`; its 166 tests stay a fixed point.
- Verified with the existing harnesses — `diagrewrite` for single rewrites and the trigger-cycle script
  for the end-to-end case — measuring both correctness and wall-clock time.

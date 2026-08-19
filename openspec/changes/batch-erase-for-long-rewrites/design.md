## Context

After 0.3.0 the insert half of a rewrite is a single clipboard paste, so what remains in a long
replacement is the erase. Measured end to end, including the read-back verification:

| Rewrite | Duration |
|---|---|
| 5 characters | 234 ms |
| 46 characters | 862 ms |
| 200 characters (the selection cap) | 3419 ms |

For 200 characters the code *reads* as 400 ms of pacing (200 backspaces × 2 ms) plus a 215 ms settle.
The other ~2.8 seconds is not the paste and not the verification: it is `Thread.Sleep(2)` not sleeping
2 ms. Windows' default timer granularity is about 15.6 ms, so each of those 200 pauses costs roughly
that, and the erase alone accounts for ~3 seconds.

This also retro-explains a measurement from the corruption investigation that looked like noise at the
time: erase pacing of 5 ms and 10 ms was no cleaner than 2 ms, and only 20 ms came out clean. Every
value below ~15 ms was landing on the same quantum, so that sweep varied a number that had almost no
effect on the actual delay. Its conclusion — that pacing is not a monotonic dial — stands, but for a
different reason than assumed.

Two constraints frame the work. First, the pacing is load-bearing: an unpaced erase corrupted the text in
4 runs out of 4 at 46 characters. Second, the erase's failure mode is the dangerous one — a dropped
backspace deletes the wrong amount of text and nothing about the resulting document says so, whereas the
insert's failure mode is a wrong string that verification catches. That asymmetry should drive the choice
of fix, not just the stopwatch.

## Goals / Non-Goals

**Goals:**

- Bring a 200-character replacement under about 1.5 seconds without reintroducing corruption.
- Keep the erase's per-event delay *real* rather than nominal, so the code's numbers mean what they say
  and the next person measuring is not misled as we were.
- Prefer an approach whose lost events are detectable over one whose lost events silently destroy text.
- Leave the short-word path untouched at ~234 ms.

**Non-Goals:**

- Changing the verification layer. It is what makes experimenting here safe, and it stays exactly as is.
- Raising the system timer resolution process-wide as a first move. `timeBeginPeriod` affects scheduling
  and power behaviour beyond this app, which is a large side effect for a text utility to impose while a
  local fix is available.
- Touching `Switcher3way.Core` or the macOS build.
- Removing the pacing. The measurement that put it there has not been invalidated — only the belief about
  what it costs.

## Decisions

### Measure the erase in isolation before changing it

Extend `diagrewrite` with an erase *strategy* argument, as it already takes pacing numbers, and use the
existing matrix harness to compare strategies on both axes that matter: text correctness and wall-clock
duration. Report the duration from the app's own log timestamps rather than from the harness, so the
figure excludes harness overhead.

Alternatives considered: change the erase and re-run the cycle test. Rejected — the cycle test answers
"did the text survive" but its timing is dominated by trigger latency and deliberate waits, so it cannot
tell a 3-second erase from a 300 ms one.

### Candidate strategies, in the order they will be tried

1. **Batched backspaces.** *k* backspaces in one `SendInput` array, one pause per batch. Cuts both the
   number of calls and, more importantly, the number of pauses by *k*. At *k*=8 the 200-character case
   drops from ~200 pauses to ~25 — roughly 400 ms — while still giving the target a real gap to breathe.
   The risk is that a batch is itself a small flood; *k* is what the matrix measures.
2. **A pause that is actually short.** Replace `Thread.Sleep(2)` with a spin-wait (`SpinWait`/
   `Stopwatch`) for sub-quantum delays, so 2 ms costs 2 ms. Keeps the current event-by-event shape and its
   proven flood characteristics, at the cost of burning CPU for the duration of a long erase — about
   400 ms of one core at 200 characters.
3. **No erase at all.** Select the range with *n* `Shift+Left` events and let the paste replace the
   selection. Removes the backspace stream entirely, and its failure mode is the safe one: a lost caret
   movement yields a shorter selection, so the paste replaces less text and verification reports a
   mismatch rather than the document quietly losing characters.

Strategy 3 is the most attractive on failure-mode grounds and the least proven — caret movement across
wrapped lines, and in targets that treat `Shift+Left` unusually, needs checking before it can be trusted.
Hence the order: 1 and 2 are cheap and low-risk to measure; 3 is measured on the same rig and adopted only
if it holds up in more than one target.

### The threshold stays where it is

Whatever wins applies only above the existing paste threshold. Short replacements are already fast and are
typed rather than pasted, which is what keeps the clipboard untouched for nearly every conversion. There is
no latency problem to solve there, so there is no reason to accept new risk there.

### Correct the record in the code

Wherever the erase pause is set, the comment must say that a bare `Thread.Sleep` of a few milliseconds is
quantised to ~15 ms on Windows. That fact cost this project one misleading measurement already, and the
number in the source looks entirely reasonable without it.

## Risks / Trade-offs

- **Batching reintroduces the corruption** → the batch factor is chosen by measurement at 46, 100 and 200
  characters, not picked; and verification catches a regression rather than shipping it.
- **A spin-wait burns CPU** → bounded by the erase length and only above the paste threshold; if it shows
  up as a problem, batching does the same job without it.
- **`Shift+Left` behaves differently across wrapped lines or in unusual targets** → verified in more than
  one application before adoption, and it is the strategy most likely to be rejected on those grounds
  despite being the most appealing on paper.
- **Faster injection may expose a target that was only ever kept correct by accident** → the same guard as
  before: the read-back reports a mismatch and the text is repaired.
- **The latency figures are from one machine** → they are recorded as such. A relative improvement measured
  the same way on the same rig is the claim, not an absolute guarantee.

## Migration Plan

No data or settings migration; the change is internal to the rewrite path. It ships in a normal version
bump to both channels. Rollback is reverting the commit, since the previous strategy remains a code path
selectable by `diagrewrite`.

## Open Questions

- Which strategy wins on the combination of speed and failure mode — the matrix decides, and the answer
  goes back into this document.
- Does the erase need pacing at all once the insert is a paste? The corruption measurement predates the
  paste path, and it is possible the unpaced erase was only fatal in combination with a per-character
  insert. Worth a cell in the matrix: unpaced erase plus paste insert, at 46 and 200 characters. If that
  is clean, the fastest fix is also the simplest one — but it would need repeating enough times to trust,
  because the failure it re-risks is silent.

## Context

See `proposal.md — Why` for the defect. What matters for the approach:

- There are **two** independent candidate builders with the same dedup pattern and no shared code:
  `NWayResolver.manualPlan` ([NWayResolver.swift](../../../Sources/Switcher3wCore/NWayResolver.swift))
  works from recorded keystrokes; `TextConverter.buildSelectionSteps`
  ([TextConverter.swift](../../../Sources/Switcher3w/TextConverter.swift)) works from already-rendered
  characters, because a selection gives text rather than keycodes. Its own comment says it "mirrors
  `NWayResolver.manualPlan`" — it mirrors the bug too.
- The promotion step already computes the right answer. `manualPlan` calls `evaluate` and gets
  `.convert(Decision)` or `.ambiguous(winners:)`; it simply has nowhere to put it once the winning
  layout has been deduped away.
- The selection builder has weaker evidence available: it re-derives validity itself and only
  promotes when *exactly one* candidate validates. It does not read the ambiguity preference at all.

## Goals / Non-Goals

**Goals:**
- One trigger tap leaves the user in the layout the evidence points at, on both paths.
- The ambiguity preference means the same thing on the trigger as it does for auto-fix.
- The visible cycle is unchanged in length and in the text it shows.

**Non-Goals:**
- Making the two builders share an implementation. They start from different inputs (keycodes vs
  characters) and the merge is a bigger change than this fix; they should agree in *behavior*, and
  the tests are what hold that.
- Changing auto-fix. It already picks by language from `evaluate`'s winners, before any dedup.
- Changing the undo cycle's restore semantics: completing the cycle still returns the exact
  pre-conversion layout, which is recorded independently of any of this.

## Decisions

### D1 — Fix the survivor's layout, don't un-collapse the candidates

When renders collide, keep one candidate and correct which layout it carries.

*Why not offer both:* a cycle step that changes no visible character reads as the trigger being
broken. The user taps, the word does not move, and the only difference is an input-source change
they may not be looking at. Two of the three installed layouts producing the same text is the
common case for uk/ru, so this would affect most Cyrillic words.

*Why not pick eagerly during the loop:* the dictionary evidence comes from `evaluate`, which the
function already calls *after* building the list. Restructuring to evaluate first would duplicate
work; adjusting the survivor afterwards is a two-line change at the existing promotion site.

### D2 — Write the order down, even though the code already computes it

Dictionary winner → ambiguity preference → rotation order. Rungs 1 and 2 are **disjoint cases**,
not competing rules: they are the two shapes `evaluate` returns (`.convert` with a single winner,
`.ambiguous` with several), and `manualPlan` already handles both. Nothing here is a new judgement.
It is written out as a requirement because the current behavior is the accident of rung 3 being the
only one that can actually take effect.

Rung 2 stays conditional on the preferred language being *among the winners* — the existing code's
condition, preserved: a preference of "ru" must not drag a uk-only word into the Russian layout.

Rung 3 covers "Do not convert". On the auto path that setting means "leave ambiguous words alone",
and it keeps that meaning there. On the trigger it reads as "no preference between uk and ru":
the trigger converts ambiguous words by design, because it is an explicit request, so refusing to
act would contradict a shipped requirement in `manual-conversion-and-undo`. Rotation order is
therefore both the sensible reading and today's behavior — rung 3 changes nothing.

### D3 — The selection path gets the same order, with the preference passed in

`buildSelectionSteps` currently promotes only when exactly one candidate validates. It gains the
same three rungs, which means it needs `SettingsManager.shared.ambiguousLang` — a read it does not
do today. `TextConverter` already reads settings elsewhere, so this introduces no new dependency
direction.

*Why not leave the selection path alone:* it is the same user action with the same expectation. A
fix that makes ⌥ behave correctly on typed words but not on selected ones is a worse state than
either consistent behavior, because it makes the rule unlearnable.

### D4 — Verification is by unit test on the core, manual on the selection path

`manualPlan` is in the core target and directly assertable, including the collapse cases that
motivated this. `buildSelectionSteps` is AppKit- and clipboard-bound and is not reachable from the
core test target; extracting it is the merge this change declines to do (see Non-Goals). It is
verified by hand against the same word list the unit tests use, and the tasks name the exact words
so the check is repeatable rather than impressionistic.

## Risks / Trade-offs

- **Users notice a different layout after ⌥** → intended, and the previous result was arbitrary
  (input-source order), not a considered default. Worth calling out in the release notes rather than
  shipping silently, since muscle memory attaches to the trigger.
- **The two builders drift again** → they are already independent; this change adds a second place
  the rule has to hold. Mitigated by tests that name the behavior rather than the function, and by a
  comment in each pointing at the other.
- **The selection path's evidence is weaker** than the keystroke path's — it validates rendered
  characters rather than re-rendering keystrokes, so an odd selection may reach rung 3 where the
  keystroke path reaches rung 1. Accepted: rung 3 is today's behavior, so the selection path can
  only improve or stay as it is.
- **`sourceLayout` inference could pick the wrong source** for text identical across layouts — a
  pre-existing weakness of the selection path that this change neither fixes nor worsens.

## Migration Plan

None. No persisted state, no settings, no UI. Each builder is independently revertable, though
shipping only one would leave the two paths disagreeing — revert both or neither.

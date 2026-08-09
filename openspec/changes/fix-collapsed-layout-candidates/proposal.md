## Why

The manual trigger builds its candidate list by rendering the keystrokes through every installed
layout and **deduplicating by the rendered string**:

```swift
var seen: Set<String> = [original]
for layout in ordered {
    guard let rendered = …, !seen.contains(rendered) else { continue }
    seen.insert(rendered)
    candidates.append(…)
}
```

Ukrainian and Russian share most of their letters on the same keys. Any Cyrillic word built purely
from those shared letters — no і/ї/є, no ы/э/ъ — therefore renders **identically** in both, and only
whichever layout comes first in the rotation survives. The promotion step that follows is supposed
to put the dictionary winner first, but it can only reorder candidates that exist: matching by
layout id finds nothing, and its fallback match by rendered string lands back on the same collapsed
entry. The layout it carries is never corrected.

The result: **the text is right and the layout is wrong.** Tap the trigger on `хорошо` — Russian
only; Ukrainian says добре/гарно — and you get the correct word while being left in the *Ukrainian*
layout, so the next thing you type comes out wrong. Whichever of uk/ru happens to sit earlier in
your input-source order wins every time, regardless of the dictionary.

The same rule silently disables the **ambiguity preference** on this path — and it does so *after*
the code has already worked out the right answer. `Settings → Auto-fix → Language for ambiguous
words` (Ukrainian / Russian / Do not convert) is read by the trigger today: `AppDelegate` passes it
into `manualPlan`, which picks the matching winner —

```swift
case .ambiguous(_, let winners):
    if ambiguousLang != "off", let w = winners.first(where: { $0.lang == ambiguousLang }) {
        promoted = (w.layoutID, w.converted)     // the correct answer, computed
    }
```

— and then loses it two lines later, because an "ambiguous" word is by definition one whose render
validates in both languages, which means the renders are identical and the preferred layout was
already deduped away. The lookup by layout id finds nothing, and its fallback by rendered text
lands back on the survivor. So the preference is honoured in intent and discarded in effect: it
works for auto-fix and does nothing for the trigger.

This is worth stating precisely, because it changes what the fix is. There is no missing mechanism
to design — the setting exists, the trigger reads it, and the intended behaviour is already
expressed in code. What is missing is somewhere to *put* the answer once the winning layout has
been collapsed away.

Both defects are in the shipping app and were found by the suite added in
`2026-08-09-windows-parity-macos`, which pinned them as passing tests rather than changing behavior
mid-extraction. The code's own comment already claims the fixed behavior — *"the preferred ambiguity
language takes that spot"* — so this brings the code up to what it says it does.

The **selection path has the same defect independently**: `TextConverter.buildSelectionSteps` builds
its own candidate list with its own `seen` set and the same dedup, so converting selected text
picks the layout the same arbitrary way.

## What Changes

- **De-duplicate candidates by rendered text *and* language**, not by text alone. Same-language
  duplicates (two Russian layouts) still collapse; uk and ru stay separate steps even when they
  spell the word identically. The text already on screen suppresses only a candidate of the source
  layout's own language.
- **Order** the candidates by the evidence the code already computes, so one tap gives the same
  answer auto-fix would: single validating language → that one; several → the **preferred ambiguity
  language** from Settings when it is among them; otherwise rotation order.
- "Do not convert" keeps meaning what it means for auto-fix on the auto path (leave the word alone)
  and reads as "no preference between uk and ru" on the trigger, which converts ambiguous words by
  design because it is an explicit request — the rotation order simply stands.
- **The cycle gains a step** for words uk and ru spell identically: one whose text is unchanged and
  whose layout differs. This reverses the first draft of this proposal, which kept a single
  candidate carrying the winning layout on the grounds that a step changing no visible character
  reads as the trigger doing nothing. That is still true, and it is the price of the alternative
  being *unreachable*: with a text-only key, the sibling language could not be offered at all when
  its render collided with the text already on screen — a selected `добре` cycled uk↔en and never
  reached ru, which is how the gap was found. Reachable-but-quiet beats unreachable.
- Fix applies to **both** candidate builders — `NWayResolver.manualPlan` and
  `TextConverter.buildSelectionSteps`.
- **BREAKING (behavior):** for words made only of letters uk and ru share, one trigger tap now
  selects a different layout than before, and the cycle is one step longer. That is the point, but
  users who learned the old arbitrary result will notice.

## Capabilities

### New Capabilities
<!-- None. This corrects existing requirements' implementation. -->

### Modified Capabilities
- `manual-conversion-and-undo`: the candidate-ordering requirement SHALL state that when layouts
  produce identical text the retained candidate carries the dictionary winner's — or the preferred
  ambiguity language's — layout, and that this applies to the selection path as well as the
  keystroke path.

## Impact

- **Code**: `Sources/Switcher3wCore/NWayResolver.swift` (`manualPlan`) and
  `Sources/Switcher3w/TextConverter.swift` (`buildSelectionSteps`). The selection path needs the
  ambiguity preference passed in, which it does not read today.
- **Tests**: `Tests/Switcher3wCoreTests/ManualPlanTests.swift` — two tests currently assert the
  defect and flip to asserting the fix; new cases for each tie-break rung. The selection path is
  not reachable from the core test target (it is AppKit/clipboard-bound), so it is covered by the
  shared helper's tests plus manual verification.
- **Risk**: user-visible. Contained to which layout becomes active after a trigger tap; the text
  produced is unchanged, and the undo cycle still restores the exact pre-conversion layout.
- **Docs**: `docs/user-guide*.md` — the trigger section says the trigger "converts to the
  best-matching layout", which only becomes true with this change; worth a sentence on what happens
  when two layouts render a word the same.

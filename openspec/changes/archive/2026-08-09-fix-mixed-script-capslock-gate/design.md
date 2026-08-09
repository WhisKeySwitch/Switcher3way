## Context

See `proposal.md — Why`. The whole surface is one function:

```swift
static func looksLikeCodeIdentifier(_ s: String) -> Bool {
    for (i, c) in s.enumerated() where i > 0 && c.isUppercase { return true }   // camelCase
    // …then: does the token contain both Latin and Cyrillic?
}
```

called from exactly one place, inside the `if !capsLock` block in `SoftGates.passes`
([SoftGates.swift](../../../Sources/Switcher3wCore/SoftGates.swift)). It is now in the core target
and directly unit-testable, which is how the gap surfaced.

## Goals / Non-Goals

**Goals:**
- Each veto is applied under the condition that actually justifies it.
- The corrected behavior is asserted by a test, not just fixed.

**Non-Goals:**
- Reconsidering *which* vetoes exist, or their thresholds (the two-letter minimum, the acronym
  rule). Those are deliberate and separately arguable.
- Widening the mixed-script definition beyond Latin+Cyrillic. Greek, Armenian and Georgian users
  exist — the interface ships in those languages — but no evidence says the current pair is
  insufficient, and guessing is how a precision-first gate turns into a blunt one.

## Decisions

### D1 — Split the function rather than pass a flag

Two named predicates, `hasInternalCapital` and `isMixedScript`, replacing the single
`looksLikeCodeIdentifier`. `passes` then reads:

```swift
if isMixedScript(typed) { return false }        // code, whatever the shift state
if !capsLock {
    if isAllCaps(typed) { return false }
    if hasInternalCapital(typed) { return false }
}
```

*Why not keep one function and pass `capsLock` into it:* the bug is precisely that one name hid
two rules with different justifications. A parameter would preserve that. Two names make the
asymmetry visible at the call site, which is where the next reader will be looking.

*Alternative rejected — leave it and document:* the veto is one comparison on a string already in
cache. There is no cost worth trading correctness for.

### D2 — Mixed-script is checked first, before the Caps Lock branch

Cheapest correct ordering and it puts the always-applied rule where it cannot be misread as part
of the exemption. Behaviorally identical to checking it inside an `else`.

## Risks / Trade-offs

- **A legitimate word is now rejected** → only possible for a token containing both Latin and
  Cyrillic letters, which is not a word in any of the app's languages. The realistic loss is a
  wrong-layout word the user typed with Caps Lock on that happens to render mixed-script; the
  manual trigger still converts it, since the trigger does not consult these gates.
- **Direction of failure** → this change can only ever *withhold* a conversion. For a
  precision-first detector that is the safe direction, and it is why the change carries no
  behind-a-setting rollout.
- **Practical impact is small** (see the proposal's scope note) → accepted; the fix is cheap and
  the alternative is leaving a gate that means two different things depending on a key nobody
  associates with alphabets.

## Migration Plan

None. No persisted state, no settings, no UI. Revert is a single-file revert.

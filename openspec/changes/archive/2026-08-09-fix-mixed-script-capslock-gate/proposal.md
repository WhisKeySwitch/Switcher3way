## Why

`SoftGates.passes` skips two vetoes when Caps Lock is on:

```swift
if !capsLock {
    if isAllCaps(typed) { return false }             // acronyms
    if looksLikeCodeIdentifier(typed) { return false } // camelCase / mixed alphabets
}
```

Skipping the first two is right. Under Caps Lock everything is uppercase, so "is it ALL CAPS?"
and "does it have an internal capital?" stop meaning anything — that is exactly why the exemption
exists.

But `looksLikeCodeIdentifier` answers **two** questions, not one: internal capital *or* a mix of
Latin and Cyrillic in the same token. The mixed-alphabet half has nothing to do with letter case.
`приvit` is code whether or not Caps Lock is down, and today it passes the gates when it is.

Found by the test suite added in `2026-08-09-windows-parity-macos`, and pinned there as
`testMixedScriptIsAllowedThroughUnderCapsLock` — a passing test documenting behavior nobody chose.
That change was a mechanical extraction and deliberately did not touch detection, so the fix was
left to this one.

**Honest scope note.** The practical exposure is small. On the N-way path the gate runs against a
candidate rendered through a *single* layout, which is all-Cyrillic or all-Latin by construction,
so a mixed-script token can barely arise there. The reachable case is the 2-way remote-desktop
path (`LayoutDetector.decide`), where the gate runs against text as it appears on screen. This is
a correctness and consistency fix, not a bug users are hitting daily — it is worth doing because
the veto is cheap, the current behavior is unintended, and a gate that silently means something
different under Caps Lock is a trap for the next person reading it.

## What Changes

- Split `looksLikeCodeIdentifier` into its two independent vetoes:
  - `hasInternalCapital` — stays Caps-Lock-gated, unchanged in meaning.
  - `isMixedScript` — applied **always**, regardless of Caps Lock.
- Update the test that currently documents the gap so it asserts the corrected behavior, and keep a
  test proving the camelCase exemption under Caps Lock still holds (that part is deliberate).
- No new settings, no UI, no user-visible surface. Detection becomes marginally *stricter*, which
  is the safe direction for a precision-first detector: the failure mode of this change is a word
  going unconverted, never a word being converted wrongly.

## Capabilities

### New Capabilities
<!-- None. This corrects an existing requirement's implementation. -->

### Modified Capabilities
- `automatic-conversion-on-word-boundaries`: the safety-gate requirement SHALL state that the
  mixed-script veto applies irrespective of Caps Lock, while the all-caps and internal-capital
  vetoes remain Caps-Lock-exempt.

## Impact

- **Code**: `Sources/Switcher3wCore/SoftGates.swift` only.
- **Tests**: `Tests/Switcher3wCoreTests/SoftGatesTests.swift` — one test flips from documenting the
  gap to asserting the fix.
- **Risk**: low. The change can only *remove* conversions, never add one. No persisted state, no
  migration, no UI.
- **Docs**: none. The user guide describes the gate as "the word looks like code", which is what it
  will now do more consistently.

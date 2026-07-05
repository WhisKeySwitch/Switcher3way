## Why

The manual ⌥ trigger still carries a two-layout design from upstream: it tries N-way detection first, but when detection is ambiguous or declines, it falls back to flipping between a fixed **Layout 1 / Layout 2** pair, and undo (`switchToOpposite`) toggles within that pair. In a 3-way (N-way) world this is both confusing and buggy:

- The **Layout 1 / Layout 2 pickers in Settings are a vestige** — they don't affect auto-fix (which is always N-way over all installed layouts) and only govern the trigger's ambiguous-case fallback and undo. Users reasonably ask what they're even for.
- The **undo is wrong in 3-way** (a known issue): after an auto-switch, ⌥-undo retypes the original text correctly but `switchToOpposite` can land on the wrong layout because it's built around a pair, not the layout that was actually active before.
- When detection is genuinely ambiguous (a word valid in both uk and ru), the trigger's fallback flips to the *other half of the pair* rather than to the layout the user actually wants — an explicit user action produces an arbitrary result.

## What Changes

- **Make the manual trigger fully N-way.** On a trigger, resolve the typed word across all installed layouts; if there's a single unambiguous target, convert and switch there (unchanged). When detection declines or is ambiguous, the trigger — being an explicit user action — SHALL still act by converting to the next candidate layout rather than doing nothing or flipping a fixed pair.
- **Replace pair-toggle undo with an N-way cycle.** Re-invoking the trigger without typing SHALL advance through the ordered candidate layouts (retyping the word in each and switching to it), and completing the cycle SHALL restore the exact original text **and the exact pre-conversion layout** — fixing the 3-way undo bug.
- **Record the pre-conversion layout** in conversion state so undo/cycle-home returns precisely to it (this also fixes the auto-switch ⌥-undo bug).
- **BREAKING (UI): remove the Layout 1 / Layout 2 pickers** from Settings ▸ General. The `layout1ID`/`layout2ID` defaults keys are deprecated (retained unread for rollback insurance) and no longer define the trigger pair.
- **Remote-desktop path:** where N-way is inapplicable (keystrokes arrive pre-rendered as characters), keep a minimal deterministic fallback (advance to the next installed layout) instead of the pair `switchToOpposite`.

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `manual-conversion-and-undo`: the trigger resolves N-way and always acts on explicit invocation; undo becomes an N-way cycle that restores the original text and the exact pre-conversion layout.
- `layout-switching-and-language-detection`: manual switching is expressed as "switch to a specific target / cycle through candidates / restore the recorded previous layout" rather than "opposite of the configured pair".
- `settings-and-exception-management`: the manual layout-pair row/pickers are removed; the Purpose and the display-name requirement drop their manual-pair references.

## Impact

- **Code:** `AppDelegate` (`onAltTap`/`onAltReconvert` orchestration), `KeyboardMonitor` (CONVERT vs RECONVERT dispatch is reused), `TextConverter` (conversion state gains the candidate cycle + pre-conversion layout; `reconvert` generalized), `LayoutSwitcher` (candidate ordering; `switchToOpposite` demoted to the remote fallback or replaced), `NWayDetector` (expose ordered candidates, not just the single-winner Decision), `SettingsWindowController`/`FormUI` (remove the pair row), `SettingsManager` (deprecate `layout1ID`/`layout2ID` as trigger inputs), `Localization` (drop/adjust pair-row strings).
- **Docs:** user guides (trigger semantics section) and any Settings screenshots/wording; the known-issue note in `CLAUDE.md` is resolved.
- **Behavior:** manual trigger no longer no-ops on ambiguous words; undo may cycle through more than two layouts. Auto-fix behavior is unchanged.
- **Defaults:** `layout1ID`/`layout2ID` become dormant (kept for rollback); one-time migration not required.

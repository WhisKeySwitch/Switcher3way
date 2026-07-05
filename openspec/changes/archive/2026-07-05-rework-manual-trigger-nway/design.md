## Context

The manual trigger flow lives in `AppDelegate.startMonitoring` (`onAltTap` / `onAltReconvert`), dispatched by `KeyboardMonitor.fireConversion` which already distinguishes **CONVERT** (keys typed since last conversion) from **RECONVERT** (no typing since). Today:

- `onAltTap` tries `NWayResolver.resolve` → if a single unambiguous target, `convertBuffer` + `switchTo(target)`; else it falls back to the 2-way `TextConverter.convert` + `LayoutSwitcher.switchToOpposite()`.
- `onAltReconvert` calls `TextConverter.reconvert()` (swaps `lastOriginal`⇄`lastConverted`) + `switchToOpposite()`.
- `switchToOpposite` toggles between `layout1ID`/`layout2ID` (or auto-detected `autoDetectID1/ID2`). The Settings General tab exposes those two as a pair.

`NWayResolver.resolve` returns a single `Decision` (target + original + converted) or `nil`. It already renders the keystrokes through every installed layout that has a dictionary — exactly the raw material needed to build an ordered candidate list. The known 3-way undo bug (CLAUDE.md) is a direct symptom of undo relying on `switchToOpposite` instead of the actually-previous layout.

## Goals / Non-Goals

**Goals:**
- Manual trigger always acts on explicit invocation, choosing an N-way target with no fixed pair.
- Repeated triggers cycle through candidate layouts and, on cycle completion, restore the exact original text and pre-conversion layout (fixes the undo bug).
- Remove the Layout 1/2 pickers; keep the defaults keys dormant for rollback.

**Non-Goals:**
- Changing auto-fix (word-boundary) behavior — it stays N-way and precision-first (still declines on ambiguous words).
- Reworking trigger key configuration (single/double tap, right-only) — unchanged.
- Migrating or deleting `layout1ID`/`layout2ID` from defaults.

## Decisions

- **Candidate cycle instead of a pair.** Introduce an ordered candidate list built from the same per-layout rendering `NWayResolver` already does. Order: start from the layout after the current one in installed order, wrap around, ending at the pre-conversion (original) layout; collapse layouts whose rendered string is identical (e.g. US/ABC) so cycling never appears to "do nothing". The N-way unambiguous winner, when present, is placed **first** so the common case (one tap → correct layout) is unchanged.
  - *Alternative considered — "last-used layout":* simpler but can't disambiguate 3+ and doesn't give the user a way to reach the third layout by tapping. Rejected.
- **Expose candidates from `NWayResolver`.** Add a resolver entry point that returns the ordered candidate layouts (each with target layout ID + converted string) rather than only the single `Decision`. The existing `resolve` stays for auto-fix (single-winner, precision-first); the new call powers the manual trigger. Keeps auto and manual policies cleanly separate.
- **Conversion state carries the cycle.** `TextConverter` conversion state gains: ordered candidates, current index, and `previousLayoutID` (the layout active before the first conversion). `convertBuffer` records these; a generalized `reconvert`/`cycleNext` advances the index, retypes from the *original* keys into candidate[i], and switches to candidate[i]'s layout. Index past the end ⇒ restore original text + `previousLayoutID`. This subsumes the current 2-way swap and fixes undo for both manual and auto conversions (auto-convert also records `previousLayoutID`).
- **`switchToOpposite` demoted.** It remains only as the remote-desktop fallback (rendering across layouts is impossible when keystrokes arrive as characters), re-specified as "advance to the next installed layout". Everywhere else, switching is explicit (`switchTo`) or cycle-driven.
- **Settings UI.** Remove the merged pair row (`SettingsWindowController` + `FormUI`) and its localized strings; `SettingsManager.layout1ID/layout2ID` accessors stay but are no longer read by trigger logic (kept for rollback). General tab keeps the status card and other rows.

## Risks / Trade-offs

- **[Behavior change users may notice]** The trigger now converts ambiguous words that it previously left alone → Mitigation: this only fires on *explicit* trigger (never auto), matching the user's intent to force a switch; cycling lets them step past an unwanted guess.
- **[Cycle disorientation with many layouts]** 4+ installed layouts make a long cycle → Mitigation: unambiguous winner is first; identical renders are collapsed; completing the cycle always returns to the exact original, so no state is unrecoverable.
- **[Undo semantics change]** Existing users expect one re-tap = undo → Mitigation: with the common 2-candidate case, one re-tap still lands back on the original text+layout, so the familiar behavior is preserved; extra candidates only appear when 3+ layouts actually render differently.
- **[Remote path divergence]** Remote fallback uses next-installed-layout, not candidate rendering → Mitigation: documented; remote is a beta flag and rendering-based cycling is fundamentally unavailable there.

## Migration Plan

1. Add candidate-list API to `NWayResolver`; unit-exercise ordering/collapsing via the debug log.
2. Extend `TextConverter` conversion state (candidates, index, `previousLayoutID`); generalize `reconvert` → cycle.
3. Rewire `AppDelegate` `onAltTap`/`onAltReconvert` to the cycle; record `previousLayoutID` in the auto-convert path too.
4. Demote `switchToOpposite` to the remote fallback.
5. Remove the Settings pair row + strings; leave defaults keys dormant.
6. Update user guides + resolve the CLAUDE.md known-issue note.

Rollback: revert the commits; dormant `layout1ID`/`layout2ID` values are still present, so re-introducing the pair UI would restore prior behavior with no data loss.

## Open Questions

- Should the status-bar flag flash on each cycle step to signal the layout change? (Leaning yes — reuse the existing `updateStatusIcon`; no new UI.)
- Do we want a visible hint (caret flag / brief HUD) showing which candidate the cycle landed on for 3+ layouts? Deferred unless testing shows it's confusing.

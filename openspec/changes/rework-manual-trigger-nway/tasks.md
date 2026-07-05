# Tasks: rework-manual-trigger-nway

## 1. Candidate resolution (NWayDetector)

- [x] 1.1 Add an ordered-candidates API to `NWayResolver` (e.g. `candidates(keys:capsLock:) -> [Candidate]` exposing target layout ID + converted string per candidate), reusing the existing per-layout render logic
- [x] 1.2 Define the ordering: unambiguous N-way winner first (when present), then remaining installed layouts starting after the current one and wrapping, with layouts whose rendered string is identical to another collapsed out; ending position returns to the original layout
- [x] 1.3 Keep the existing single-winner `resolve` intact for auto-fix; add debug `rslog` of the computed candidate order

## 2. Conversion state + cycle (TextConverter)

- [x] 2.1 Extend conversion state to hold the ordered candidates, the current cycle index, and `previousLayoutID` (layout active before the first conversion)
- [x] 2.2 Record candidates + `previousLayoutID` in `convertBuffer` (and set index to the first applied candidate)
- [x] 2.3 Generalize `reconvert` into a cycle step: retype from the original keys into the next candidate and report its target layout ID; when advancing past the last candidate, restore the original text
- [x] 2.4 Preserve trailing-space handling and the clipboard fallback path unchanged

## 3. Orchestration (AppDelegate + KeyboardMonitor)

- [x] 3.1 Rewrite `onAltTap`: build candidates, convert to the first target, switch to its layout, and store the cycle + `previousLayoutID`; on ambiguous/declined detection convert to the first alternative candidate instead of falling back to the pair
- [x] 3.2 Rewrite `onAltReconvert`: advance the cycle (retype + `switchTo` next candidate); on cycle completion restore original text and re-select `previousLayoutID`
- [x] 3.3 Record `previousLayoutID` in the auto-convert path (`handleAutoConvert`) so ⌥-undo after an auto-switch restores the exact prior layout (fixes the known 3-way undo bug)
- [x] 3.4 Keep CONVERT vs RECONVERT dispatch in `KeyboardMonitor` as-is; confirm buffer-reset guards still fire on typing/arrows/app-switch

## 4. Layout switching (LayoutSwitcher)

- [x] 4.1 Demote `switchToOpposite` to the remote-desktop fallback only; re-implement it (or add a sibling) as "advance to the next installed input source"
- [x] 4.2 Point the remote-desktop trigger paths in `AppDelegate` at that fallback; remove pair (`layout1ID`/`layout2ID`) reads from `LayoutSwitcher`/`DynamicKeyMapping` trigger logic

## 5. Settings UI + defaults

- [x] 5.1 Remove the merged "toggles between X ⇄ Y" pair row from `SettingsWindowController` (and its `FormUI` helpers) in the General tab
- [x] 5.2 Stop reading `layout1ID`/`layout2ID` for trigger behavior (accessors kept, dormant rollback insurance). Pair-row localized strings left in `Localization.swift` as dormant/unused (harmless; not deleting across 16 languages)
- [x] 5.3 Verify General tab still lays out cleanly (status card + remaining rows) with Auto Layout

## 6. Docs & verification

- [x] 6.1 Update `docs/user-guide.md` (+ `.uk.md`, `.ru.md`) trigger/undo sections to describe N-way convert + candidate cycling; regenerate in-app help via the build
- [x] 6.2 Resolve the "⌥ undo layout" known-issue note in `CLAUDE.md` (and remove the Layout 1/2 picker mention from the architecture/settings notes)
- [x] 6.3a Build (clean), install, launch: monitoring starts, permissions OK, no crash; Settings pair row removed at compile time
- [ ] 6.3b **Runtime typing check (needs a real keyboard):** single tap converts (unambiguous + ambiguous word), repeated taps cycle through 3 layouts and return to the exact original text + layout, and ⌥-undo after an auto-switch restores the correct layout

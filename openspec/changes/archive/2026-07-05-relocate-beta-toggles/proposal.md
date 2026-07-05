## Why

The Auto-fix tab currently mixes its primary control (the "Fix layout automatically as I type" master toggle) with two experimental, rarely-touched options — "Show layout flag at the cursor" and "Remote Desktop mode". The BETA badge on the master toggle undersells a shipping, on-by-invitation feature, and the two experimental toggles clutter the tab a user visits mainly to manage exceptions. Grouping the experimental toggles under Advanced (next to Debug logging) matches user expectation and declutters Auto-fix.

## What Changes

- Remove the **BETA** badge from the Auto-fix master toggle ("Fix layout automatically as I type"). Its behavior and persisted key are unchanged.
- Move **"Show layout flag at the cursor"** out of the Auto-fix tab to the **top of the Advanced tab**, keeping its BETA badge and behavior.
- Move **"Remote Desktop mode (beta)"** out of the Auto-fix tab to the **top of the Advanced tab** (above Debug logging), keeping its "(beta)" label, its `showRemoteDesktopBeta` gate, and its behavior.
- The Auto-fix tab retains only the master toggle and the unified exceptions list.

No behavior, persisted defaults keys, menu-bar toggles, or localization strings change — this is purely where controls appear in Settings and one badge removal.

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `settings-and-exception-management`: the Auto-fix master toggle no longer displays a beta badge; the caret-flag and remote-desktop toggles are presented at the top of the Advanced tab rather than in the Auto-fix tab.

## Impact

- **Code**: `Sources/Switcher3w/SettingsWindowController.swift` — `buildAutofixTab()` (drop the caret box, drop the remote box, drop the badge argument on the master row) and `buildAdvancedTab()` (prepend the caret and remote boxes above the debug box). No changes to `SettingsManager`, menu building, or feature logic.
- **Specs**: `openspec/specs/settings-and-exception-management/spec.md`.
- **No impact** on persisted UserDefaults keys, the menu-bar quick toggles, localization, or the caret-flag / remote-desktop feature behavior.

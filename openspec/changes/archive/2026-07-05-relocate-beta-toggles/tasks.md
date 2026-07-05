## 1. Auto-fix tab

- [x] 1.1 In `buildAutofixTab()` (`SettingsWindowController.swift`), remove the `badge: L10n.commonBeta` argument from the master toggle row so "Fix layout automatically as I type" shows no BETA badge.
- [x] 1.2 Remove the `caretBox` construction (including the `caretFlagSwitch = cfSwitch` capture) and the `remoteBox` block from `buildAutofixTab()`; the tab's `sections` array should start with `[masterBox]` followed by the exceptions header and pane.

## 2. Advanced tab

- [x] 2.1 In `buildAdvancedTab()`, build the caret-flag `FormBox` (retaining `caretFlagSwitch` capture, `L10n.settingsAutofixCaretFlag` title, BETA badge, and `caretFlagChanged` action) and prepend it to the tab's sections.
- [x] 2.2 In `buildAdvancedTab()`, build the remote-desktop `FormBox` behind the `settings.showRemoteDesktopBeta` guard (same title/subtitle/`remoteDesktopChanged` action as before) and place it after the caret-flag box and before `debugBox`.
- [x] 2.3 Confirm the final Advanced section order is: caret flag → remote desktop (when beta-gated) → debug box → "Show Log File" button → log-path footnote.

## 3. Verify

- [x] 3.1 `bash build_app.sh` builds cleanly with no new warnings.
- [x] 3.2 Launch the app; Settings ▸ Auto-fix shows only the master toggle (no BETA badge) and the exceptions list.
- [x] 3.3 Settings ▸ Advanced shows the caret-flag toggle and (when `showRemoteDesktopBeta` is on) the remote-desktop toggle above the debug-logging controls; toggling each still persists and applies as before.
- [x] 3.4 `openspec validate relocate-beta-toggles` passes.

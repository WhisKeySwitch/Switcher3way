## Context

The Settings window is built in code (`SettingsWindowController.swift`) with no storyboard. Each tab is assembled by a `build<Tab>Tab()` method returning a stack of `FormBox` sections. Today `buildAutofixTab()` produces three sections — the master toggle (`masterBox`, carrying a `L10n.commonBeta` badge), the caret-flag toggle (`caretBox`), and the remote-desktop toggle (`remoteBox`, gated behind `settings.showRemoteDesktopBeta`) — plus the exceptions list. `buildAdvancedTab()` produces the debug-logging box, a "Show Log File" button, and the log-path footnote.

This change is pure view composition: it relocates two `FormBox` sections from one tab-builder to another and drops one badge argument. No settings keys, actions, callbacks, menu items, or feature code change.

## Goals / Non-Goals

**Goals:**
- Remove the beta badge from the Auto-fix master toggle row.
- Present the caret-flag and remote-desktop toggles at the top of the Advanced tab, above the debug-logging controls.
- Preserve the `showRemoteDesktopBeta` gate on the remote-desktop toggle.
- Keep every persisted key, action selector, and feature behavior identical.

**Non-Goals:**
- Removing or changing either feature's behavior (that was considered separately and reverted).
- Touching the menu-bar quick toggles, localization strings, or `SettingsManager`.
- Reworking tab sizing (the tallest-tab sizing and top-alignment already exist).

## Decisions

- **Move the section builders, not just the controls.** Lift the `caretBox`/`remoteBox` construction (including `caretFlagSwitch` capture and the `showRemoteDesktopBeta` guard) verbatim into `buildAdvancedTab()`, prepended before `debugBox` in the section array. Keeping them as whole `FormBox`es preserves their grouped-card look and the existing `updateCaretFlagState`/`onCaretFlagChanged` wiring unchanged. Alternative — a shared helper returning the boxes — is overkill for two call sites now reduced to one.
- **Drop only the `badge:` argument** on the master row in `buildAutofixTab()`; leave the row title/subtitle and switch intact. `FormUI.row(badge:)` already treats badge as optional, so omitting it is the whole change.
- **Advanced tab order:** caret flag → remote desktop (if beta-gated) → debug box → Show Log File button → path footnote. This puts the relocated experimental toggles "at the top" as requested, above the pre-existing diagnostics controls.

## Risks / Trade-offs

- [Advanced tab grows taller, affecting the uniform tab-height sizing] → The tallest-tab sizing in `showWindow()` recomputes `maxH` from all tabs' `fittingSize`, and the recently added top-alignment sends slack to the bottom; both adapt automatically. No manual height constants to update.
- [`caretFlagSwitch` is stored to sync state from the menu toggle] → The property and its `updateCaretFlagState`/`onCaretFlagChanged` paths are unchanged; only the switch's parent tab differs, which the sync logic does not depend on.

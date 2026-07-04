# Tasks: modernize-ui

## 1. Foundations

- [x] 1.1 Add new `L10n` keys (English + 15 translations): "Auto-fix" tab name, status card titles/subtitle, group headers (Trigger, Manual pair, System, Exceptions, Quick toggles), pause items (Pause Switcher3way, Resume, 30 minutes, 1 hour, Until restart), onboarding strings (window title/subtitle, permission row titles + one-line explanations, Granted, Open Settings, Continue, step label, reset notice), "always off" badge, "+ Add app…" / "+ Add word…", search placeholder, exceptions footer hint
- [x] 1.2 Add `SettingsManager` pause state: session `pausedUntilRestart` flag + `com.ruswitcher.pausedUntil` date, computed `isPaused`, and a single `applyEnabledState()` path in AppDelegate that starts/stops monitoring from `autoSwitchEnabled` + `isPaused`
- [x] 1.3 Build the `FormBox` grouped-section helper (rows via NSStackView, hairline separators, section header labels) used by Settings tabs and the onboarding checklist

## 2. Settings window shell (W1/W2 chrome)

- [x] 2.1 Replace the raw `NSTabView` in `SettingsWindowController` with an `NSTabViewController` (`tabStyle = .toolbar`, `window.toolbarStyle = .preference`), SF Symbol icons, tab order General / Auto-fix / Advanced / About, per-tab `preferredContentSize`
- [x] 2.2 Verify build + manual check: tabs render as toolbar icons, window resizes per tab, existing tab content still functions before rework

## 3. General tab (W1)

- [x] 3.1 Rebuild General as grouped form: status card ("Switcher3way is On/Off" + trigger reminder + NSSwitch bound to `autoSwitchEnabled`) at top
- [x] 3.2 Trigger group: "Convert with" popup, "Right key only" switch, "Require double tap" switch, footnote "Tap the chosen key by itself…"
- [x] 3.3 Manual pair group: single "Trigger toggles between X ⇄ Y" row with two layout popups writing `layout1ID`/`layout2ID`, footnote about auto-fix covering all layouts
- [x] 3.4 System group: "Launch at login" switch, "Remember layout per app" switch, "Interface language" popup; delete the old hand-placed controls this replaces

## 4. Auto-fix tab (W2)

- [x] 4.1 Master card "Fix layout automatically as I type" with BETA badge, subtitle, switch (`autoConvert`); row "Show layout flag at the cursor" with BETA badge, switch (`caretFlag`); keep remote-desktop row behind its beta flag
- [x] 4.2 Build `ExceptionsPane`: one NSTableView + segmented filter with live counts (Apps / Never convert / Always convert) + NSSearchField, backed by three adapters refactored out of `ExceptionListEditor`
- [x] 4.3 Add affordances: "+ Add app…" (NSOpenPanel) on the Apps segment, "+ Add word…" text entry on word segments; remove disabled for empty selection and for protected rows
- [x] 4.4 Protected password-manager rows: "always off" badge, remove disabled; footer hint about ⌥ undo offering to add to Never convert (behavior already exists)

## 5. Onboarding window (W3)

- [x] 5.1 Create `OnboardingWindowController.swift`: icon, title "Set up Switcher3way", subtitle, checklist (Accessibility, Input Monitoring with restart note, Launch-at-login switch), step label + Continue button
- [x] 5.2 Live status: 1 s polling of `AXIsProcessTrusted()` / `CGPreflightListenEventAccess()` while visible; rows flip to "Granted"; timer invalidated on close; preserve automatic relaunch after Input Monitoring grant
- [x] 5.3 Rewire `runPermissionWizard` to the window: missing permissions → show window; all granted (interactive check) → window in completed state; permissions-reset path keeps tccutil logic with a reset notice in the window; delete `showStep_Accessibility`, `showStep_InputMonitoring`, `showPermissionsOKAlert`, `offerLaunchAtLoginIfNeeded` alerts (keep `launchAtLoginAsked` semantics)

## 6. Menu-bar menu (W4)

- [x] 6.1 Status header custom-view NSMenuItem: layout badge (two-letter code chip) + localized layout name, "⌥ converts last word" reminder + version; remove the old disabled version line
- [x] 6.2 Quick toggles section: header + Auto-fix / Layout sound / Flag at cursor items without "(beta)" suffixes, checkmark states
- [x] 6.3 Pause submenu (30 min / 1 h / until restart) replacing the enable item; Resume item while paused; timed auto-resume via Timer; paused status-icon treatment; Settings status card stays in sync
- [x] 6.4 "Check Permissions…" appears only when a permission is missing and opens the onboarding window; menu rebuild triggered when permission state changes (extend the 2 s safety timer path)

## 7. Verification & polish

- [ ] 7.1 Full manual pass against wireframes W1–W4 with the installed signed build (`bash build_app.sh`, copy to /Applications): each tab, exceptions filtering/search/add/remove, onboarding live-grant flow, pause/resume, conditional permissions item
- [ ] 7.2 Localization smoke test: switch interface language (en/ru/uk) and confirm new strings localize and menu rebuilds
- [x] 7.3 Regression check: manual ⌥ conversion, auto-convert, undo-learn prompt, per-app layout memory, debug log lines still correct; update NOTES-3WAY.md / CLAUDE.md UI descriptions

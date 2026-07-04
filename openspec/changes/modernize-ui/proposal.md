# Proposal: modernize-ui

## Why

The app's UI is inherited from upstream RuSwitcher and predates modern macOS conventions: bare checkboxes and hand-placed controls in Settings, three cramped 96-px exception tables with easy-to-miss +/− buttons, 3–5 chained modal NSAlerts for permission onboarding, and a menu-bar menu that buries app state. A reviewed design handoff (`inspect-and-suggest-improvements/project/Switcher3way Review.dc.html`, section **1b**, wireframes W1–W4) specifies an improved direction: same feature set, regrouped into native macOS 13+ patterns (grouped forms, switches, toolbar tabs, a persistent onboarding checklist, a status-first menu).

## What Changes

- **W1 · Settings ▸ General** — regrouped form: master on/off promoted to a status card with an `NSSwitch`; Trigger group (trigger key popup, "Right key only", "Require double tap"); "Manual pair" group merging the Layout 1 / Layout 2 popups into a single "toggles between X ⇄ Y" row; System group (launch at login, per-app layout memory, interface language). Toolbar-style icon tabs replace the segmented tab strip; tab order becomes General / Auto-fix / Advanced / About.
- **W2 · Settings ▸ Auto-fix** — tab renamed from "Auto-conversion" to "Auto-fix". Master card for automatic conversion + flag-at-cursor row, both as switches with BETA badges. The three stacked exception tables are replaced by one full-height list with a segmented filter (Apps / Never convert / Always convert) showing counts, a search field, an explicit "+ Add app…" button (NSOpenPanel picker for the Apps filter, text entry for word lists), and a "🔒 always off" badge on protected password-manager rows instead of unexplained gray text.
- **W3 · Onboarding** — the chained permission NSAlerts (Accessibility → Input Monitoring → Launch at Login → All granted) are replaced by one persistent checklist window with live grant detection, per-permission one-line explanations, an inline launch-at-login switch, and step progress. Closing the window loses nothing; it can be reopened.
- **W4 · Menu-bar menu** — status-first redesign: header row shows the current layout (badge + name), a trigger reminder, and the version (version line removed from the top). "Enable Switcher3way" is reframed as a **Pause** submenu with durations (30 min / 1 h / until restart); pausing changes the status icon so a disabled switcher never looks enabled. Quick-toggles group (Auto-fix, Layout sound, Flag at cursor) without beta labels. "Check Permissions…" leaves the daily menu and appears only when permissions are broken.
- All new/changed strings go through `L10n` with English fallback; existing 16-language keys are reused where copy is unchanged.

Non-goals: no changes to detection logic (`NWayDetector`), conversion engine, or settings storage keys (`com.ruswitcher.*` stay). The wireframe hint "undo offers to add the word to Never convert" is copy-adjusted to describe existing behavior, not a new feature.

## Capabilities

### New Capabilities

_None — this change regroups and re-presents existing capabilities._

### Modified Capabilities

- `settings-and-exception-management`: Settings window requirements change — toolbar icon tabs, new tab order and "Auto-fix" naming, grouped-form General tab with merged manual-pair row, unified exceptions list with segmented filter/search/add-app picker, protected-row badge.
- `permission-and-startup-lifecycle`: onboarding requirement changes from sequential modal alerts to a single persistent checklist window with live permission polling and integrated launch-at-login prompt.
- `menu-bar-ui-and-status-icon`: menu requirements change — status header (current layout, trigger hint, version), quick-toggle group without beta suffixes, Pause submenu with timed durations replacing the enable checkbox, paused-state icon, conditional "Check Permissions…" item.

## Impact

- **Code**: `SettingsWindowController.swift` (major rework), `AppDelegate.swift` (`rebuildMenu`, permission-wizard flow, enable/pause state), new `OnboardingWindowController.swift`, `SettingsManager.swift` (pause-until timestamp; existing keys untouched), `Localization.swift` (new/renamed strings ×16 languages).
- **Behavior**: pause introduces a timed re-enable (new UserDefaults key); everything else is presentation-level.
- **No impact**: detection/conversion pipeline, layout switching, signing/build scripts, updater (stays disabled).

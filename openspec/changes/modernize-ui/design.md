# Design: modernize-ui

## Context

The design source is `inspect-and-suggest-improvements/project/Switcher3way Review.dc.html`, section 1b (wireframes W1–W4). The wireframes are HTML prototypes; per the handoff README the job is to match the *visual output and interaction model* in native AppKit, not to port the HTML.

Current implementation facts that shape the design:

- `SettingsWindowController` builds four `NSTabViewItem`s inside a plain `NSTabView` with hand-placed frames (`createGeneralTab` etc., [SettingsWindowController.swift:44-52](Sources/RuSwitcher/SettingsWindowController.swift#L44-L52)). Exceptions use three `ExceptionListEditor` instances stacked vertically.
- The permission wizard is a chain of modal `NSAlert`s driven from `runPermissionWizard` ([AppDelegate.swift:128](Sources/RuSwitcher/AppDelegate.swift#L128)): Accessibility step → Input Monitoring step → permissions-reset path → `showPermissionsOKAlert`, plus two more one-shot alerts (`offerLaunchAtLoginIfNeeded`, `offerAutoConvertIfNeeded`).
- `rebuildMenu` ([AppDelegate.swift:485](Sources/RuSwitcher/AppDelegate.swift#L485)) builds: disabled version line, four/five toggles with "(beta)" in some labels, Check Permissions…, Settings…, Quit. Master enable is the `autoSwitchEnabled` UserDefault.
- The "undo teaches Never convert" behavior in the W2 footnote **already exists** (`offerExceptionAfterUndo`, [AppDelegate.swift:73](Sources/RuSwitcher/AppDelegate.swift#L73)) — the hint copy is accurate, no new behavior needed.
- All strings go through `L10n` (16 languages, English fallback). Settings keys are literal `com.ruswitcher.*` and must not change.
- Upstream code comments are in Russian; keep that style in edited files.

## Goals / Non-Goals

**Goals:**
- Match wireframes W1–W4 in native AppKit on macOS 13+ (the package's minimum).
- Keep every persisted key and every behavioral pipeline (detection, conversion, undo-learn, per-app memory) untouched.
- Reuse existing `L10n` keys where copy is unchanged; add new keys with English fallback and translate the 16 languages.

**Non-Goals:**
- No SwiftUI migration; the app is AppKit and stays AppKit.
- No changes to `NWayDetector`, `TextConverter`, `KeyboardMonitor` logic.
- No dark-mode-specific art: system controls adapt automatically; the wireframes are grayscale by intent.
- The first-run "enable auto-convert?" offer (`offerAutoConvertIfNeeded`) stays a separate lightweight prompt — the wireframes don't cover it and folding it into onboarding is out of scope.

## Decisions

### D1 — Settings window: `NSTabViewController` with `.toolbar` style
Replace the raw `NSTabView` with an `NSTabViewController` (`tabStyle = .toolbar`) hosted in the settings window with `window.toolbarStyle = .preference`. That is the standard way to get System-Settings-like icon tabs on macOS 13+, gives the highlighted-tab behavior of W1/W2 for free, and lets each tab be its own view controller. Tab icons use SF Symbols (`gearshape`, `wand.and.stars`, `slider.horizontal.3`, `info.circle`). Alternative considered: keep `NSTabView` and restyle — rejected, it can't produce toolbar tabs.

Window resizes per tab (preference-pane behavior comes with `NSTabViewController` toolbar style). Tab order: General, Auto-fix, Advanced, About.

### D2 — Grouped form sections: small reusable `FormBox` helper, not a framework
The grouped white boxes with hairline separators (W1/W2) are built with a small private helper (an `NSBox`-based or layer-backed container view producing rows with separators), added to `SettingsWindowController`. Rows are `NSStackView`-based: label left, control right. This replaces hand-placed `y` coordinates in the reworked tabs. Alternatives: SwiftUI `Form` inside `NSHostingView` — rejected (new paradigm in an AppKit codebase, Non-Goal); continue absolute frames — rejected (the grouped design flexes vertically).

Booleans become `NSSwitch` (native, macOS 10.15+). Popups stay `NSPopUpButton`.

### D3 — Exceptions UI: one `NSTableView` + `NSSegmentedControl` + `NSSearchField`, refactoring `ExceptionListEditor`
`ExceptionListEditor` already encapsulates list + add/remove + protected-row logic per list. Refactor rather than rewrite: a new `ExceptionsPane` owns one table, one search field, one add button, and three data adapters (apps / never words / always words) built from the existing editor logic. The segmented control swaps the active adapter and re-titles the add button ("+ Add app…" ⇄ "+ Add word…"); segment labels include live counts ("Apps (13)"). Search filters the adapter's items array; adds/removes operate on the unfiltered store.

Protected password-manager rows: render an "always off" badge (`NSTextField` pill or `NSButton` styled as badge) on the trailing edge and disable removal — replacing today's gray-text-only treatment. App rows keep their icon and gain the secondary text from the wireframe only where we have real data (bundle name); the wireframe's category captions ("terminal", "IDE") are illustrative and are dropped.

### D4 — Onboarding: new `OnboardingWindowController`, polling for live status
New file `OnboardingWindowController.swift`: a fixed-size non-modal `NSWindow` (floating level, centered) with icon, title, subtitle, a `FormBox` checklist of Accessibility / Input Monitoring / Launch-at-login rows, and a footer (step label + Continue). A 1-second `Timer` polls `AXIsProcessTrusted()` and `CGPreflightListenEventAccess()` while the window is visible; rows flip to "Granted" live, matching the existing polling approach the alert wizard already uses for restart detection. When Input Monitoring flips to granted, the existing automatic-relaunch path is kept.

`runPermissionWizard` becomes: all granted → same as today (start monitoring; interactive check shows the window in its "all granted" state instead of `showPermissionsOKAlert`); anything missing → show the onboarding window. The chained `showStep_Accessibility` / `showStep_InputMonitoring` / `offerLaunchAtLoginIfNeeded` alerts are removed; the permissions-reset path (tccutil reset) keeps its logic but its user-facing surface becomes the onboarding window with a one-line reset notice. `launchAtLoginAsked` is retained as the flag that suppresses re-prompting; the inline switch writes `launchAtLogin` directly.

Alternative considered: sheet on the settings window — rejected; onboarding happens before the user has any window open.

### D5 — Menu: keep `NSMenu`, custom view only for the header
The status header (layout badge + name + trigger reminder + version) is an `NSMenuItem` with a custom `NSView` — standard technique, keyboard-skipped automatically since it has no action. Everything else stays plain `NSMenuItem`s to preserve native behavior: "Quick toggles" becomes a section header (disabled small-caps item on 13, `NSMenuItem.sectionHeader` when available) followed by the three toggles with checkmarks (wireframe shows switches; native menus use checkmarks — intent is "toggle with visible state", checkmarks are the platform-correct rendering). Beta suffixes are dropped from menu labels only.

The header's layout badge is the two-letter language code in a rounded rect (matches W4's "EN" chip); the status *icon* in the menu bar keeps the existing emoji flag — W4 does not change it.

### D6 — Pause: `pausedUntil` timestamp on top of the existing enable flag
New UserDefaults key `com.ruswitcher.pausedUntil` (Date; absent/past = not paused). Pause submenu items (30 min / 1 h / until restart) set it; "until restart" uses a session-only flag, not persistence, so a relaunch always resumes. A pause: stops monitoring exactly like `autoSwitchEnabled = false` does today but *without* touching the `autoSwitch` key, so the user's persistent preference survives. A `Timer` scheduled at the deadline re-enables and rebuilds the menu. While paused the status icon shows a paused glyph (`⏸` prefix on the flag) so the state is visible at a glance. `autoSwitchEnabled == false` (turned off in Settings) renders the same paused icon.

Rationale for a separate key: reusing `autoSwitch` would persist "off" across restarts, breaking "until restart" semantics and silently flipping the user's saved preference.

### D7 — Conditional permissions item
`rebuildMenu` already runs on lifecycle changes; it adds "Check Permissions…" only when `!(AXIsProcessTrusted() && CGPreflightListenEventAccess())`, and the item opens the onboarding window. A permissions loss between rebuilds is caught by the existing 2-second safety timer path calling `updateStatusIcon` — extend it to trigger a menu rebuild when permission state changes.

### D8 — Localization
New keys (status card, group headers, pause items, onboarding rows, badges, "Auto-fix" tab name) go into `Localization.swift` for all 16 languages, machine-translated in the same style as existing entries, with `s()` English fallback guaranteeing nothing breaks if a language is missed. Renamed concepts reuse existing keys where the string is unchanged (e.g. `menuQuit`, `menuSettings`).

## Risks / Trade-offs

- [`NSTabViewController` toolbar-style resizing can fight fixed-size tab views] → give each tab an explicit `preferredContentSize`; verify tab switching animates to the right heights on 13 and 26.
- [Rewriting `SettingsWindowController` (569 lines, hand-placed frames) wholesale is the riskiest step] → do it tab-by-tab (General, then Auto-fix, then Advanced/About which barely change), building and manually testing after each tab; no behavior wiring changes, only re-parenting controls into `FormBox` rows.
- [Pause interacts with the menu toggle, Settings status card, and per-app layout restore] → single source of truth: a computed `isPaused` on `SettingsManager`; every surface reads it; monitoring start/stop goes through one `applyEnabledState()` function in AppDelegate.
- [Onboarding polling timer could keep firing after window closes] → invalidate on `windowWillClose`; timer holds `weak self`.
- [16-language translations for ~25 new strings are a large diff] → mechanical, English-fallback protected; review only en/ru/uk carefully (the app's core audience).
- [No automated tests in repo] → verification is the manual loop: `bash build_app.sh`, install, grant-check via debug log, walk each wireframe against the running app.

## Open Questions

- None blocking. One deliberate deviation to confirm at review: menu quick toggles render as native checkmarks, not literal switch controls (D5).

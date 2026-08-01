# Windows UI Redesign (WinUI 3)

## Why

The Windows engine is complete, but every visible surface is a dated WinForms shell: a 468×470
`FixedDialog` with a `TabControl` and hand-placed frames, a 13-item `ContextMenuStrip`, an MSHTML
`WebBrowser` Help window, and a raw-Markdown update dialog. Beyond looking old, the current UI has
real gaps: a **successful auto-fix produces no feedback at all** (the only notification is the "can't
change text" error), release notes render as literal `## What's new` / `-`, the exceptions manager
requires typing `.exe` names by hand, and there is no first-run experience. This change recreates
every surface in **WinUI 3 (Windows App SDK)** — high-fidelity to the approved design set — following
the OS light/dark theme and the user's accent colour, and closes those UX gaps.

No engine, detection, keyboard-hook, settings-persistence, or localisation logic changes. `Engine`,
`SettingsManager`, `Loc`, `StartupShortcut`, `UpdateChecker`, `UpdateInstaller`, `Diagnostics`,
`HelpContent`'s Markdown conversion, and the tray icon rendering all keep their current behavior.

## What Changes

- **Framework.** The WinForms UI (`TrayApp`, `SettingsForm`, `HelpWindow`, `UpdatePromptForm`) is
  rebuilt in WinUI 3 / XAML using stock controls and theme resources (`SettingsCard`, `ToggleSwitch`,
  `ComboBox`, `SelectorBar`, `MenuFlyout`, `AppNotification`, `ThemeResource` brushes) — no custom
  drawing where a stock control exists. Approved option set: `1a` (Settings shell + General), `1b`
  (Auto-fix + inline exceptions), `1c`'s **Add-an-app picker**, `1d` (tray flyout), `1f`+`1g`
  (feedback), `1i` (onboarding), `1j` (update + Help). Not building `1e`, `1h`.
- **Immediate-apply settings (behavior change).** Each control writes straight to `SettingsManager`
  and calls `Save()`; the Save/Cancel pair and `SettingsForm`'s working copies + `Apply()` are gone,
  leaving `Close` only. Interface-language changes re-render the open window in place; exceptions
  edits persist on the spot.
- **Conversion feedback (new).** A successful fix shows a transient, click-through **caret chip**
  (`1f`) with the struck-through keystrokes → converted word and an undo hint. Errors and the
  remember-word prompt use actionable **toasts** (`1g`): the error toast replaces the balloon tip; the
  success/prompt toast (errors + the "remember this word?" case only) carries **Undo** and **Never
  convert this** (appends to `NeverConvertWords`). No Action-Center toast per successful fix.
- **First-run onboarding (new).** A one-time 3-step flow (`1i`): what it does, detected layouts +
  dictionary readiness, and trigger-key choice with a **live try-it** running the real resolver.
  Gated by a new `HasCompletedOnboarding` flag; no OS permission grants are needed on Windows.
- **Exceptions rebuilt.** Segmented Apps / Never / Always switcher with live counts; rows show the
  **real app icon** (`ExtractAssociatedIcon`/`SHGetFileInfo`) and **friendly name** (`FileDescription`)
  beside the `.exe`; protected apps are locked/non-removable; add via a **running-app picker** (`1c`)
  or by **dropping an .exe**; word segments keep the text-entry + Add affordance. List data ellipsises,
  never wraps.
- **Rendered content.** The update prompt parses `UpdateInfo.Notes` Markdown into bullets (Skip
  demoted to a hyperlink); Help gets a table of contents generated from the guide's `##` headings,
  language pills (EN/УК/РУ), and a rendered guide (WebView2 or native XAML) replacing the `WebBrowser`.
- **Advanced tab absorbs** Debug logging and Open log folder (moved out of the tray menu, dropping it
  from 13 rows to 9); the tray flyout gains a live status header (layout + on/paused) and shortcut hints.
- **Live consistency.** The tray flyout, status card, and Settings window observe the **same**
  `SettingsManager` instance, so a toggle flipped in one surface reflects in the others without reopening.

## Capabilities

### New Capabilities

_None (all requirements land under `windows-platform-support`)._

### Modified Capabilities

- `windows-platform-support`: the tray surface becomes a status-and-toggles flyout (debug/log moved
  to Settings); **new** requirements — apply settings immediately (no Save step); show conversion
  feedback (caret chip + actionable toasts with Undo / Never-convert-this); guide first-run setup
  (onboarding, persisted); manage exception apps visually (running-app picker, icons, friendly names,
  drag-drop, protected locked); render release notes and help as formatted content.

## Impact

- **Replaced** (WinForms → WinUI 3): `TrayApp.cs`, `SettingsForm.cs`, `HelpWindow.cs`,
  `UpdatePromptForm.cs`; new views for the status card, tray flyout, exceptions panel + app picker,
  conversion feedback (caret-chip layered window + `AppNotification`), onboarding (3 steps), update
  dialog, Help window.
- **Unchanged APIs** (consumed as-is): `SettingsManager` (+ new `HasCompletedOnboarding` bool),
  `Engine`, `Loc` (+ new description/onboarding/feedback/empty-state strings for 16 locales),
  `StartupShortcut`, `UpdateChecker`/`UpdateInstaller`, `Diagnostics`, `HelpContent`.
- **Engine wiring:** `Engine.Notify` (error) plus a new success/feedback signal carrying original +
  converted + target language, consumed by the caret chip and toast; `TrayApp`'s 400 ms `RefreshIcon`
  poll and `CurrentLang` feed the status surfaces.
- **Project/packaging:** a WinUI 3 (Windows App SDK) app project; NotifyIcon is not in the SDK
  (H.NotifyIcon.WinUI or a small Win32 tray host); WebView2 for Help; layered window for the chip.
  Interaction with the current self-contained MSI + in-app updater is a design decision (see design.md).
- **Assets:** reuse `assets/en|uk|ru.png` and `assets/icon.png` / `Switcher3way.ico`; glyphs from
  Segoe Fluent Icons; app-row icons extracted at runtime.
- `docs/user-guide*.md` remains the Help source (its Markdown → TOC + body).

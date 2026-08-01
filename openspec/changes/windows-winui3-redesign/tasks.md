# Tasks — Windows UI Redesign (WinUI 3)

Land in phase order; each phase is independently shippable. Build the parallel WinUI project sharing
`Core`/`Engine`/`SettingsManager`, cut over when at parity (confirm parallel-vs-in-place first).

## 0. Walking skeleton (platform seams)

- [ ] 0.1 Add a WinUI 3 app project (Windows App SDK, **unpackaged, self-contained**:
  `WindowsPackageType=None`, `WindowsAppSDKSelfContained=true`, apphost `.exe`) referencing
  `Switcher3way.Core` + `Switcher3way.Dictionaries`; keep `AssemblyName=Switcher3way`.
- [ ] 0.2 Single-instance + app lifecycle (reuse the existing mutex); theme = `Default` +
  `UISettings.ColorValuesChanged`; accent = system accent; no in-app theme switch.
- [ ] 0.3 Tray host with `H.NotifyIcon.WinUI`: reuse `TrayApp.MakeFlag` + the 400 ms `RefreshIcon`
  poll (dimmed/pause-bars when `!EffectivelyEnabled`); a stub flyout.
- [ ] 0.4 `AppNotification` registration for unpackaged (AUMID + Start-menu shortcut + activation
  handler); one round-trip test toast; fall back to the balloon tip if registration fails.
- [ ] 0.5 Confirm `build-msi.ps1` stages the WinAppSDK runtime via `dotnet publish`; MSI + updater
  still install/relaunch the `.exe`.

## 1. Shared plumbing

- [ ] 1.1 `SettingsManager`: add `HasCompletedOnboarding` (bool, persisted). Wrap the process-wide
  instance in a thin observable (`Changed` event / `INotifyPropertyChanged`) all surfaces subscribe to.
- [ ] 1.2 Immediate-apply: delete `SettingsForm`'s `_apps/_never/_always` working copies + `Apply()`;
  each control setter writes the property and calls `Save()` now (including `StartupShortcut.Set` and
  `Loc.Configure` on change).
- [ ] 1.3 `Engine`: add a success feedback signal `event Action<ConversionInfo> Converted`
  (`original`, `converted`, `targetLang`, `canUndo`) raised after a successful auto/manual fix; keep
  `Notify` for errors. Undo reuses the manual-undo path.
- [ ] 1.4 `Loc`: add new keys — SettingsCard descriptions (`settings.*.desc`), exceptions group
  headers + empty states, `Add app…`/picker, onboarding copy, feedback chip/toast text; English +
  16-locale translation (fallback to English). Re-word `settings.launchAtLogin` → **Start with Windows**.
- [ ] 1.5 Move `SecureField` UIA off WPF `System.Windows.Automation` to COM `UIAutomationClient`; drop
  the WPF reference from the WinUI project.

## 2. Settings shell + General (`1a`)

- [ ] 2.1 620px window, Mica, extended custom title bar (40px, app icon + "Switcher3way" + caption
  buttons); `SelectorBar` tab strip (General / Auto-fix / Advanced / About) — not `TabView`.
- [ ] 2.2 Status card (General only): 26×19 flag, "`<lang>` — current layout", "N layouts installed ·
  dictionaries ready", and an Active/Paused pill (caution colours + remaining time when paused). Live
  from the 400 ms poll.
- [ ] 2.3 General cards via `SettingsCard` (collapsed borders, group headers): Enable, Remember-per-app,
  Start-with-Windows; Trigger group — trigger-key ComboBox (mono keycap + chevron; items/order from
  `SettingsForm.TriggerKeys`) and Interface-language ComboBox (`SettingsForm.Languages`, System default first).
- [ ] 2.4 Footer: "Changes apply as you make them" + `Close` only.

## 3. Auto-fix + exceptions (`1b`) + app picker (`1c`)

- [ ] 3.1 Auto-fix group: Fix-automatically toggle; Language-for-ambiguous-words ComboBox
  (Українська / Русский / Do not convert → `AmbiguousLang`), the hint promoted to a wrapping description
  (card grows, not fixed height).
- [ ] 3.2 Exceptions panel: `SelectorBar` segments Apps / Never convert / Always convert with live
  counts (`DeniedApps`+`ProtectedApps`, `NeverConvertWords`, `AlwaysConvertWords`); search box filters live.
- [ ] 3.3 Grouped list with sticky headers ("Always off — password managers, not removable" =
  `ProtectedApps`; "Added by you" = `DeniedApps`): 44px rows, real icon (`ExtractAssociatedIcon`/
  `SHGetFileInfo`, cached) + friendly name (`FileDescription`) + `.exe`; protected rows locked (no
  remove); user rows have a remove button; text ellipsises, never wraps.
- [ ] 3.4 Footer: accent `+ Add app…` opening the `1c` picker; `.exe` drop target; Never/Always
  segments swap the footer to a text box + `Add`.
- [ ] 3.5 Add-an-app picker (`ContentDialog`): running processes with a visible top-level window,
  de-duped by path, excluding listed; checkbox rows (icon + friendly name + `.exe`); primary counts the
  selection ("Add N app(s)"); `Browse for .exe…` via `FileOpenPicker`. (Two-pane full page from `1c` is
  a fallback only if the inline block gets crowded once localised.)

## 4. Advanced + About

- [ ] 4.1 Advanced: Check-for-updates + Debug-logging toggles; an Open-log-folder card whose
  description shows `Diagnostics.FilePath` in selectable mono. (These move here from the tray.)
- [ ] 4.2 About: icon, name, tagline (`win.tagline`), `Version {Major}.{Minor}`, MIT/fork line,
  Website + GitHub `HyperlinkButton`s.

## 5. Tray flyout (`1d`)

- [ ] 5.1 290px flyout: header (flag + layout + "Auto-fix on · F9 to convert"); toggle rows (Enable /
  Auto-fix / Remember-per-app) with small `ToggleSwitch`es; `Pause…` submenu (30 min / 1 hour / Until
  restart), showing `Resume` + paused header when paused.
- [ ] 5.2 Settings… (`Ctrl+,`), Help (`F1`), Check-for-updates… (busy label swap on
  `UpdateChecker.IsBusy`), Quit — with mono shortcut hints. Full keyboard navigation + focus visuals.

## 6. Conversion feedback (`1f` + `1g`)

- [ ] 6.1 Caret chip: click-through layered overlay (`WS_EX_LAYERED|TRANSPARENT|NOACTIVATE|TOPMOST`),
  positioned via UIA `GetBoundingRectangles` → `GetCaretPos` → tray fallback; success dot, struck-through
  mono keystrokes → mono converted word, divider, trigger-keycap + "undo". Fade 200/hold 1600/out 120 ms;
  cancel-and-reshow on a new fix. Keycap follows `TriggerKey` ("Shift Shift" for double-tap).
- [ ] 6.2 Toasts (`AppNotification`), two cases only: error (replaces balloon; elevation copy) and the
  remember-word prompt (Undo / Never convert this → `NeverConvertWords`). No toast per successful fix.
- [ ] 6.3 Wire both to `Engine.Converted` / `Engine.Notify` on the dispatcher.

## 7. First run (`1i`)

- [ ] 7.1 520px, 3 steps, shown once when `!HasCompletedOnboarding`; shared 40px title bar + footer
  with step dots + nav buttons.
- [ ] 7.2 Step 1 welcome (headline + paragraph + demo chip). Step 2 layouts: one row per
  `InstalledLayouts()` with dictionary-ready/caution pill from `HunspellDictionaryValidator.IsAvailable`,
  plus the ambiguity caution bar. Step 3 trigger: three radio cards (F9 / Right Ctrl / Shift Shift) +
  live try-it running the real `NWayResolver` + Start-with-Windows checkbox.
- [ ] 7.3 Persist the chosen trigger + startup; set `HasCompletedOnboarding` on Finish.

## 8. Update prompt + Help (`1j`)

- [ ] 8.1 Update `ContentDialog`: title/subtitle (`update.available.title` / `update.installed` + "The
  app restarts itself to finish"); WHAT'S NEW card rendering `UpdateInfo.Notes` Markdown as bullets
  (reuse the `HelpContent` subset parser); `Install and restart` / `Later` / `Skip this version`
  (hyperlink). No raw markup.
- [ ] 8.2 Help window: 172px TOC from the guide's `##` headings; `WebView2` rendering `HelpContent`
  HTML; EN/УК/РУ language pills (replace the `help:` scheme); external links → default browser; keep
  the worked-example table in the guide.

## 9. Localisation, empty states, polish, verification

- [ ] 9.1 Empty states: protected-only apps list → "No apps added yet."; empty Never/Always →
  "Nothing here yet — undo a fix with F9 to add a word."
- [ ] 9.2 Verify wrap-vs-ellipsis under German/Ukrainian: SettingsCard descriptions wrap and grow;
  list-row data ellipsises. Focus rectangles on every interactive element incl. the tray flyout.
- [ ] 9.3 Theme parity pass (light + dark) against the option screenshots; confirm accent follows the
  Windows accent colour.
- [ ] 9.4 Smoke test end-to-end: settings immediate-apply across surfaces; a real fix shows the chip;
  error shows the toast; onboarding once; update renders bullets; Help TOC + language switch; MSI
  install + updater relaunch of the WinUI build.

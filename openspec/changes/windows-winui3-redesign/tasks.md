# Tasks — Windows UI Redesign (WinUI 3)

Landed on the `windows-winui3` branch (PR #42), in-place and skeleton-first: phase 0 stood up a
running WinUI app model, and every later phase added real screens, so the branch built and ran
throughout. Version **0.2.0**.

Where reality diverged from the plan it is noted inline and recorded in design.md decisions 13–15
(Store packaging, Win32 tray, hand-built cards).

## 0. Walking skeleton (platform seams)

- [x] 0.1 Convert `Switcher3way.App` to WinUI 3 **in place** (Windows App SDK; `UseWinUI`, apphost
  `.exe`, single-instance mutex and `selftest` kept; WinForms/WPF app model retired).
- [x] 0.2 Single-instance + lifecycle; theme follows the OS; system accent colour.
- [x] 0.3 Tray host — **direct Win32 `Shell_NotifyIcon`**, not H.NotifyIcon (decision 14); reuses the
  existing flag rendering and the 400 ms poll (dimmed + pause bars when off).
- [ ] 0.4 `AppNotification` registration for unpackaged toasts — **not done**; toasts were not built
  (see 6.2). Packaged builds get identity for free, so this only matters for the MSI channel.
- [x] 0.5 Build/packaging verified: `Directory.Build.props` points at VS's PRI/MSIX tooling;
  `build-msi.ps1` reworked for the WinUI reality (WinAppSDK left as a runtime dependency,
  `-p:Platform=x64`); `build-msix.ps1` added.

## 1. Shared plumbing

- [x] 1.1 `HasCompletedOnboarding` added; settings shared as one instance across surfaces.
- [x] 1.2 Immediate-apply: working copies and `Apply()` gone; every control writes + `Save()`s now,
  including `StartupShortcut.Set` and `Loc.Configure`.
- [x] 1.3 `Engine.Converted` event (`ConversionInfo`) raised from the single-word, phrase-correction
  and manual paths; never on an aborted/failed rewrite or the restore step.
- [~] 1.4 `Loc` wiring — done via a `{app:Loc}` markup extension plus in-place `ApplyLanguage()`.
  **Partial:** the description/prose strings written for this redesign have no translation keys yet,
  so they are English in every language.
- [x] 1.5 `SecureField` re-implemented without WPF: `ES_PASSWORD` + MSAA `STATE_SYSTEM_PROTECTED`
  (this covers browser password inputs); suppression is logged.

## 2. Settings shell + General (`1a`)

- [x] 2.1 620px window, `SelectorBar` tabs (not `TabView`).
- [x] 2.2 Status card — layout, installed count, Active/Paused pill, live.
- [x] 2.3 General cards — Enable / Remember-per-app / Start-with-Windows, trigger-key and
  interface-language combos (same items and order as before).
- [x] 2.4 Footer: "Changes apply as you make them" + `Close` only.

## 3. Auto-fix + exceptions (`1b`) + app picker (`1c`)

- [x] 3.1 Auto-fix toggle + ambiguous-language combo with the hint promoted to a wrapping description.
- [x] 3.2 Segmented Apps / Never / Always with live counts + search.
- [x] 3.3 Grouped list with real app icons and friendly names; protected rows locked; user rows
  removable; text ellipsises.
- [x] 3.4 Footer swaps between "+ Add app…" and text-box + Add.
- [ ] 3.5 Add-an-app picker — **built** (running apps, de-duped, counted primary button,
  `Browse for .exe…`), except the **drag-and-drop `.exe`** target from the design.

## 4. Advanced + About

- [x] 4.1 Advanced: update + debug toggles, log path in selectable mono, Open-log-folder (moved off
  the tray, per the design).
- [x] 4.2 About: icon, name, tagline, version, MIT/fork line, Website + GitHub links.

## 5. Tray flyout (`1d`)

- [x] 5.1 Fluent flyout — status header, three toggle switches, pause durations that swap to Resume;
  implemented as a real borderless window (decision 14), positioned by the work area, hides on
  deactivate.
- [x] 5.2 Settings (`Ctrl+,` hint), Help, Check-for-updates, Quit.

## 6. Conversion feedback (`1f` + `1g`)

- [x] 6.1 Caret chip — click-through layered window, DPI-scaled, caret-anchored with documented
  fallbacks, fade in/hold/out, keycap names the configured trigger.
- [ ] 6.2 Toasts — **not built.** The error case still only logs, and the remember-word prompt does
  not exist; the "Surface errors and prompts as actionable notifications" requirement is unmet.
- [x] 6.3 Feedback wired from the engine onto the UI thread.

## 7. First run (`1i`)

- [x] 7.1 520/560px window, three steps, shown once, step dots + navigation.
- [x] 7.2 Welcome; layouts step with dictionary-ready/caution pills; trigger step with a live try-it
  that runs the real resolver.
- [x] 7.3 Trigger + start-with-Windows persisted; `HasCompletedOnboarding` set on Finish (and on
  failure, so the flow can never block startup).

## 8. Update prompt + Help (`1j`)

- [x] 8.1 Update prompt as its own window (no XamlRoot in a tray-only app) with release notes
  **rendered** as headings + accent bullets; Install / Later / Skip-as-hyperlink; also serves the
  up-to-date and error messages.
- [x] 8.2 Help window: WebView2 over the existing `HelpContent` HTML, section TOC from the guide's
  own headings, EN/УК/РУ pills, external links to the browser, graceful message if WebView2 is absent.

## 9. Localisation, empty states, polish, verification

- [x] 9.1 Empty states for the apps and word lists.
- [~] 9.2 Ellipsis-vs-wrap behaviour implemented; a German/Ukrainian overflow pass is still untested
  in practice. Focus visuals come from the stock controls.
- [x] 9.3 Light/dark follow the OS; accent is the system accent.
- [x] 9.4 Smoke-tested end to end by the user: tray + flyout, Settings (all four tabs, immediate
  apply, language switch), conversion chip, selection conversion, onboarding, updater ("up to date"),
  Help. Both channels build at 0.2.0 (MSIX 12.4 MB, MSI 35.2 MB).

## 10. Store distribution (added — decision 13)

- [x] 10.1 MSIX flavour from the same project (`-p:Packaged=true`), real Partner Center identity
  (Store ID 9MXFXL7GG3C5), `runFullTrust` + `startupTask` declared, tile/splash assets generated.
- [x] 10.2 `PackageInfo.IsPackaged`; packaged builds never self-update and use the package StartupTask.
- [x] 10.3 Windows App Certification Kit run: 22 pass / 1 warning / 1 optional fail. Fixed the DPI
  declaration (`app.manifest`, PerMonitorV2) and moved packaged launches to `Windows.System.Launcher`;
  remaining flags are false positives (dictionary words "bash"/"reg"; "MSBuild" inside Microsoft's own
  `WinRT.Runtime.dll`).
- [x] 10.4 Privacy policy published (`docs/privacy.html`, linked from both landing pages) — the Store
  requires one for an app that can access personal information — plus a submission pack in
  `RELEASING.md` (justification + notes for certification).
- [ ] 10.5 Submit to Partner Center and get `runFullTrust` approved — **outstanding, and outside the
  repo**: screenshots still need capturing, and the review latency is unknown.

## Deferred (tracked, not done)

- [ ] Toasts (6.2) and unpackaged notification registration (0.4).
- [ ] UIA-based caret position, so the chip is accurate in apps with no classic caret (Chrome,
  VS Code, Electron) instead of falling back to the window corner.
- [ ] Translation keys for the new description/prose strings (1.4).
- [ ] Drag-and-drop `.exe` onto the exceptions panel (3.5).
- [ ] Delete the superseded WinForms files (`TrayApp.cs`, `SettingsForm.cs`, `UpdatePromptForm.cs`),
  excluded from the build but still present.

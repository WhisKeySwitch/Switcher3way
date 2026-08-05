# Tasks — Windows UI Redesign (WinUI 3)

Landed on the `windows-winui3` branch (PR #42), in-place and skeleton-first: phase 0 stood up a
running WinUI app model, and every later phase added real screens, so the branch built and ran
throughout. First shipped as **0.2.0**; reconciled here against **0.2.3**, which is what is public.

Where reality diverged from the plan it is noted inline and recorded in design.md decisions 13–19
(Store packaging, Win32 tray, hand-built cards, then four things only shipping revealed: the publish
step dropping compiled XAML, WinUI ending the message loop with the last window, the bootstrapper
being unusable in a packaged app, and .NET having to be bundled for the Store).

Releases: 0.2.0 (withdrawn — see 11.1), 0.2.1, 0.2.2, 0.2.3.

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
- [x] 1.4 `Loc` wiring — a `{app:Loc}` markup extension plus in-place `ApplyLanguage()`.
  Shipped partial in 0.2.0–0.2.2 (Settings had 21 strings through `Loc` and ~28 hard-coded; onboarding
  had none), **completed in 0.2.3**: ~50 new keys translated for en/uk/ru, `ApplyLanguage()` now also
  runs at construction so the first-open and language-change paths cannot drift, and `Loc.IsComplete`
  labels the 13 languages that still fall back to English as *partly translated* in the picker.
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
- [~] 9.2 Ellipsis-vs-wrap behaviour implemented. A Ukrainian/Russian overflow pass was done in 0.2.3
  once those languages had real strings, and found two clipped elements — the onboarding keycap
  ("Pause/Brea") and the step-2 InfoBar, fixed by narrower keycap padding and a 700px window.
  **Still untested:** German and the other partly-translated languages. Focus visuals are stock.
- [x] 9.3 Light/dark follow the OS; accent is the system accent.
- [x] 9.4 Smoke-tested end to end by the user: tray + flyout, Settings (all four tabs, immediate
  apply, language switch), conversion chip, selection conversion, onboarding, updater ("up to date"),
  Help. Re-verified on the *installed* artifact from 0.2.1 onwards (see 11.1) and, for the packaged
  flavour, on the sideloaded MSIX. Channel sizes at 0.2.3: MSI 35.3 MB, MSIX 44.5 MB (decision 19).

## 10. Store distribution (added — decision 13)

- [x] 10.1 MSIX flavour from the same project (`-p:Packaged=true`), real Partner Center identity
  (Store ID 9MXFXL7GG3C5), `runFullTrust` + `startupTask` declared, tile/splash assets generated.
- [x] 10.2 `PackageInfo.IsPackaged`; packaged builds never self-update and use the package StartupTask.
- [x] 10.3 Windows App Certification Kit: **OVERALL PASS**, 23 of 24 tests. Fixed the DPI declaration
  (`app.manifest`, PerMonitorV2) and moved packaged launches to `Windows.System.Launcher`. The one
  failure is the optional "Blocked executables" test, which no .NET app can pass: its 18 messages are
  the bundled runtime (`coreclr.dll`, `clrjit.dll`, `System.Private.CoreLib.dll`,
  `System.Diagnostics.Process.dll`), the WinAppSDK bootstrapper, the apphost's own `ShellExecuteW`
  import, and substring hits like `en.dic` containing the word "bash". Our own managed
  `Process.Start` reference *was* removed (decision 18), taking the findings from 19 to 18.
- [x] 10.4 Privacy policy published (`docs/privacy.html`, linked from both landing pages) — the Store
  requires one for an app that can access personal information — plus a submission pack in
  `RELEASING.md` (justification + notes for certification). Extended afterwards: the policy now
  discloses the clipboard round-trip the manual trigger performs (`Ctrl+C`, read, restore), which it
  had never mentioned, and `windows/store-listing.md` holds the listing copy, screenshot plan and
  captions in en/uk/ru.
- [x] 10.5 **Submitted to Partner Center on 5 August 2026** (package
  `Switcher3way-0.2.3-x64-store.msix`, validated). Screenshots captured by the user; the
  `runFullTrust` justification is in `RELEASING.md` in three lengths because the submission field
  turned out to be exactly 500 characters. **Approval still pending** — a restricted capability is
  reviewed by hand.

## 11. Post-release fixes (added — found by shipping)

- [x] 11.1 **The 0.2.0 MSI could not open a single window.** `dotnet publish` does not carry the
  compiled XAML (`.xbf`, `resources.pri`) into the publish folder for an unpackaged WinUI app, so the
  installed app showed its tray icon, fell back to the native menu, and threw `XamlParseException` for
  every window. Fixed by a `PublishXamlResources` target that copies them and **fails the build** if
  none are found; 0.2.0 was withdrawn (release notes rewritten, MSI asset deleted, so the updater
  skips it). Root cause of the verification gap: only Debug builds from `bin` had ever been tested,
  never the installed artifact. Every release since is verified after installation.
- [x] 11.2 **The app quit when its last window closed** (decision 17) — fresh install → welcome flow →
  Finish → process exits instead of settling into the tray. Fixed with a never-activated keep-alive
  window.
- [x] 11.3 **The Store build never started** (decision 18) — `Bootstrap.TryInitialize` is for apps with
  no package identity and fails inside MSIX, so the packaged app showed "Windows App Runtime 1.6 isn't
  installed" and exited. Now gated on `PackageInfo.IsPackaged`.
- [x] 11.4 **The Store package contained no .NET** (decision 19) — framework-dependent, so it would
  have installed from the Store and failed to launch on any PC without .NET 8. Now built
  `-p:SelfContained=true`, with the build refusing to finish if `System.Private.CoreLib.dll` is
  missing. 12.4 MB → 44.5 MB.
- [x] 11.5 Trigger default changed to a **double tap of Ctrl** (was F9: behind `Fn` on many laptops and
  claimed by other apps). Existing installs keep their choice; the picker leads with
  Double Ctrl / Pause/Break / F9.
- [x] 11.6 Store and sideload packages no longer overwrite each other — both modes wrote the same
  `AppPackages` path, and a dev-signed package is rejected on upload. Each now lands in
  `windows/dist/` as `…-x64-{store,sideload}.msix`, with the build hard-failing a Store package whose
  Publisher is not the Partner Center one.
- [x] 11.7 The MSI installer's licence page no longer renders mangled text (an RTF `\par` that ate the
  first word of every line), and `LICENSE` now ships beside the exe in both flavours, as MIT requires.

## Deferred (tracked, not done)

- [ ] Toasts (6.2) and unpackaged notification registration (0.4) — the "surface errors and prompts as
  actionable notifications" requirement remains unmet; failures still only reach the debug log.
- [ ] UIA-based caret position, so the chip is accurate in apps with no classic caret (Chrome,
  VS Code, Electron) instead of falling back to the window corner.
- [ ] Translations for the remaining 13 interface languages (~50 keys each). They fall back to English
  and the picker labels them partly translated, so this is visible rather than silent.
- [ ] Drag-and-drop `.exe` onto the exceptions panel (3.5).
- [ ] Delete the superseded WinForms files (`TrayApp.cs`, `SettingsForm.cs`, `UpdatePromptForm.cs`),
  excluded from the build but still present.
- [ ] arm64 build; x64 runs under emulation on Windows-on-ARM but is untested there.

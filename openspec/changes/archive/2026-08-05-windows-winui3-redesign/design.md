# Design — Windows UI Redesign (WinUI 3)

## Context

Today the Windows app is `net8.0-windows` WinForms (+ WPF only for UIA password detection). The UI
lives in `TrayApp.cs` (NotifyIcon + `ContextMenuStrip`), `SettingsForm.cs` (TabControl, working
copies + `Apply()`), `HelpWindow.cs`/`HelpContent.cs` (MSHTML `WebBrowser` over generated HTML), and
`UpdatePromptForm.cs`. The engine, settings, hook, updater, diagnostics, and localisation are done
and stay. This change is a **presentation-layer rewrite** to WinUI 3 with a few decided behavior
changes (immediate-apply settings; conversion feedback; onboarding). The approved visual spec is the
handoff's option set; every colour/size/copy there is authoritative and maps to WinUI theme resources.

The hard parts are not the XAML — they are the platform seams a WinForms app got for free: a tray
icon, a click-through caret overlay, actionable toasts, and how all of that coexists with the current
**unpackaged self-contained MSI + SHA-256 in-app updater**.

## Goals / Non-Goals

**Goals**
- High-fidelity WinUI 3 recreation of `1a/1b/1c-picker/1d/1f/1g/1i/1j`, light + dark, following the OS
  theme and the user's accent colour (no brand colour, no in-app theme switch).
- Close the UX gaps: silent success → caret chip; raw Markdown → rendered notes/help; type-the-exe →
  app picker; no first run → onboarding.
- Preserve the current distribution model (MSI + updater) and every non-UI API.

**Non-Goals**
- Any engine / detection / hook / persistence / localisation *logic* change.
- Options `1e` (status flyout) and `1h` (layout HUD).
- MSIX/Store packaging; changing the tray icon's flag rendering; a settings redesign beyond the specced surfaces.

## Decisions

1. ~~**Unpackaged, self-contained Windows App SDK — keep the MSI + updater.**~~ **SUPERSEDED — see
   Decision 13.** The original reasoning was that MSIX would discard the MSI/updater pipeline *and*
   hard-require a paid signing certificate just to install. The second half stopped being true when
   Microsoft made individual Store accounts free, which changed the answer.

2. ~~**Tray icon via `H.NotifyIcon.WinUI`.**~~ **SUPERSEDED — see Decision 14.** The package
   installs the icon fine, but its menu **clicks never route** in an unpackaged tray-only app.

3. **Caret chip is a Win32 layered overlay, not a WinUI window.** `1f` must be **click-through and
   never focused**, which WinUI top-level windows resist. Use a lightweight layered window
   (`WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE | WS_EX_TOPMOST`, `SetWindowPos` with
   `SWP_NOACTIVATE`) drawn via composition/GDI+, positioned from the caret rect:
   `IUIAutomationTextRange.GetBoundingRectangles` → `GetCaretPos`/`GUITHREADINFO` → tray corner
   fallback. Fade in 200 ms / hold 1.6 s / fade out 120 ms; cancel-and-reshow if another fix lands.
   The keycap label follows `Settings.TriggerKey` ("Shift Shift" for double-tap).

4. **Toasts via `AppNotification`, registered for unpackaged.** On startup register an AUMID +
   Start-menu shortcut and `AppNotificationManager.Default.Register()` with an activation handler, so
   unpackaged toasts work and their buttons round-trip. Only two cases raise a toast: the **error**
   (replaces the balloon tip; `Engine.Notify`) and the **remember-word prompt** (Undo / Never convert
   this → append to `NeverConvertWords`). **Never one toast per successful fix.** Everyday success is
   the caret chip only.

5. **Feedback signal from the engine.** Add a lightweight success event alongside `Engine.Notify`,
   e.g. `event Action<ConversionInfo> Converted` carrying `(original, converted, targetLang, canUndo)`,
   raised from the worker thread after a successful `AutoConvert`/manual fix. The UI marshals it to the
   dispatcher and shows the chip; the toast's Undo reuses the existing manual-undo path. This is UI
   plumbing, not a detection change.

6. **Immediate-apply via a shared settings view-model.** One process-wide `SettingsManager` instance
   wrapped in a thin observable (`INotifyPropertyChanged` or a `Changed` event). Each control two-way
   binds; a setter writes the property and calls `Save()` immediately — deleting `SettingsForm`'s
   `_apps/_never/_always` working copies and `Apply()`, including the deferred `StartupShortcut.Set`
   and `Loc.Configure` (now fired on change). All surfaces (tray flyout, status card, Settings)
   subscribe, so a toggle in one updates the others live (today `TrayApp.UpdateUi()` only runs after
   the dialog closes). Interface-language change re-resolves `Loc` and re-renders the open window.

7. **Help = WebView2 over the existing `HelpContent` HTML.** Reuse `HelpContent`'s Markdown→HTML
   conversion (the single source of truth) rendered in `WebView2`, keeping the in-app language switch
   and routing `http(s)` links to the default browser (as `HelpWindow` does today). The `1j` TOC is
   built from the guide's `##` headings; the worked-example table is authored into the guide/HTML.
   *Rejected:* native XAML `RichTextBlock` rendering — it would fork the Markdown pipeline. Cost:
   WebView2 runtime dependency (present on Win11; note it for older targets).

8. **Release-notes Markdown → bullets** reuses the same minimal Markdown subset `HelpContent` already
   parses (headings + `-` bullets), rendered as an `ItemsControl` of bullet rows — no raw `## ` / `-`
   leaking, no new dependency.

9. **Exceptions data.** Friendly name from the executable's `FileDescription` version resource; icon
   via `ExtractAssociatedIcon`/`SHGetFileInfo` (cached by path). The picker enumerates running
   processes owning a visible top-level window, de-duped by path, excluding already-listed apps;
   `Browse for .exe…` uses `FileOpenPicker`; the panel is an `.exe` drop target. `ProtectedApps` rows
   are locked/non-removable (today's `Tag="protected"` rule). Row data uses `TextTrimming`
   (ellipsis), never wrap; SettingsCard descriptions wrap and grow the card.

10. **UIA stays via COM.** Password-field detection (`SecureField`) keeps using UI Automation through
    the COM `UIAutomationClient` interop rather than WPF's `System.Windows.Automation`, so the WPF
    reference can be dropped from the WinUI project.

11. **Onboarding.** A normal WinUI window shown once when `!Settings.HasCompletedOnboarding`; step 2
    reads `Win32LayoutCatalog.InstalledLayouts()` + `HunspellDictionaryValidator.IsAvailable`; step 3's
    try-it runs the real `NWayResolver` on what the user types and shows the would-be conversion, then
    persists the chosen trigger and `Start with Windows`. Setting the flag on Finish gates future launches.

13. **Dual distribution: MSIX to the Microsoft Store (primary) + the MSI (secondary).** Replaces
    Decision 1. Individual Store accounts became free, and the Store **signs submitted packages** —
    which removes the SmartScreen "unknown publisher" warning without an OV/EV certificate, the one
    blocker we could not solve ourselves. One project builds both flavours (`-p:Packaged=true` for
    MSIX); `PackageInfo.IsPackaged` detects which is running, so packaged builds never self-update
    (Store policy) and use the package **StartupTask** instead of a Startup-folder shortcut.
    Measured: Store MSIX **12.4 MB** (the WinAppSDK framework is a shared Store dependency) vs MSI
    **35.2 MB** vs the outgoing WinForms MSI 55.2 MB. Costs, accepted: `runFullTrust` is a
    *restricted* capability, so every submission is reviewed by hand with a written justification;
    and **self-contained WinAppSDK cannot be produced in this environment at all**, so the MSI
    channel depends on "Windows App Runtime 1.6" being installed — the app now says so plainly
    instead of exiting silently.

14. **Tray is direct Win32 (`Shell_NotifyIcon` + `TrackPopupMenuEx`), and the Fluent flyout is a real
    window.** Replaces Decision 2. H.NotifyIcon's WinUI flyout renders but its item clicks were never
    delivered — verified by file logging that the handler was never entered — in either
    `ContextFlyout` or `ContextMenuMode.PopupMenu`, and hosting the icon inside a hidden window did
    not help; a tray-only app has no reliable `XamlRoot` for a flyout. `TrackPopupMenuEx(TPM_RETURNCMD)`
    returns the chosen command id synchronously, so nothing can silently fail. The designed Fluent
    look (`1d`) is then a small borderless always-on-top **window** with real WinUI controls, with the
    native menu kept as an automatic fallback if it ever fails to show.

15. **SettingsCard rows are hand-built, not CommunityToolkit.** `CommunityToolkit.WinUI.Controls.SettingsControls`
    transitively pulls in **Uno.WinUI**, which conflicts with WinAppSDK and breaks the XAML compiler.
    A `Border` + `Grid` with a shared style reproduces the design without the dependency.

12. **In-place migration on a feature branch, skeleton-first (no parallel project) — user decision.**
    Convert the existing `Switcher3way.App` from WinForms to WinUI 3 **in place** — one project, one
    build, one updater — rather than standing up a second project. Because WinForms and WinUI 3 can't
    share an app model, phase 0 replaces the app model and stands up a **running** WinUI skeleton
    (window + tray + one toast); every later phase adds real screens, so the app builds and runs
    throughout the port, only missing not-yet-ported surfaces. Do the work on a `windows-winui3`
    feature branch so `main` keeps shipping the WinForms 0.1.x MSI, and merge at parity. *Rejected:* a
    parallel `Switcher3way.App.WinUI` — it avoids a broken branch mid-port but adds a second csproj,
    duplicate wiring, and a shared-library extraction; the branch model gives the same "`main` stays
    shippable" guarantee without them.

16. **The publish step must copy the compiled XAML, and the build must fail if it cannot.**
    `dotnet publish` leaves `.xbf` and `resources.pri` behind for an *unpackaged* WinUI app even though
    both sit in `$(OutDir)`. The result is not a crash on startup but something worse: the app runs, its
    Win32 tray icon appears, and every attempt to open a window throws `XamlParseException` — so it
    looks half-dead rather than broken, which is how 0.2.0 shipped. A `PublishXamlResources` target copies
    them and errors when none are found. *Packaged builds are unaffected*: MSIX embeds the compiled XAML
    in `resources.pri` instead of shipping loose `.xbf`, so the same failure cannot occur there.

17. **A tray-first app needs a keep-alive window.** WinUI ends the message loop when the last window
    closes, which for an app with no main window means the process dies the moment the user closes
    Settings — or, on a fresh install, the moment they press Finish in the welcome flow. It stayed
    hidden through three releases because opening the tray flyout once leaves a hidden window alive, and
    every existing install had done that; only a genuinely new user hit it. A `Window` that is created
    and never activated is never shown and keeps the loop running; "Quit" goes through
    `Application.Exit()`, which ignores it.

18. **Packaged builds must not touch the bootstrapper, and must not contain process-launching code.**
    `Bootstrap.TryInitialize` exists to find a Windows App Runtime for apps with *no package identity*;
    inside MSIX the runtime arrives through the manifest's framework dependency and the call fails — so
    the Store build displayed "Windows App Runtime 1.6 isn't installed" on a machine where it plainly
    was, and exited. Gated on `PackageInfo.IsPackaged`. Separately, the packaged flavour compiles out the
    `ShellExecute` fallbacks and swaps `UpdateInstaller` for a stub, so the assembly holds no
    `Process.Start`, `msiexec` or MSI relauncher: a Store build must not self-update anyway, and the App
    Certification Kit reads the binary rather than the reachable code. A `#if` cannot cover the updater —
    the C# lexer scans *skipped* regions for directives, and the relauncher is a raw string whose
    PowerShell `#` comments then parse as malformed ones (CS1024) — hence one file per flavour.

19. **The Store package bundles .NET; only the WinAppSDK stays a framework dependency.** Refines
    decision 13. MSIX can declare a dependency on `Microsoft.WindowsAppRuntime.1.6` and the Store
    resolves it, but there is no equivalent for the .NET runtime: a framework-dependent package installs
    from the Store and then fails to launch on any PC without .NET 8, which defeats the only advantage
    the Store channel has over the MSI. Built `-p:SelfContained=true`, with the build refusing to finish
    if `System.Private.CoreLib.dll` is absent from the package. The **12.4 MB measured in decision 13
    was only achievable because .NET was missing**; the honest figure is **44.5 MB** against the MSI's
    35.3 MB.

## Risks / Trade-offs

- **WinUI-3-unpackaged + self-contained is the least-trodden path** (notifications/registration, tray
  via third-party, larger binary). → Prove a walking skeleton first (window + tray + one toast) before
  porting screens.
- **AppNotification registration for unpackaged apps is fiddly** (AUMID + shortcut + COM activator). →
  Encapsulate in one startup helper; fall back to the existing balloon tip if registration fails.
- **Caret-rect accuracy varies by app** (UIA not implemented everywhere). → The documented
  UIA→GetCaretPos→tray fallback chain; the chip is best-effort and never blocks the fix.
- **WebView2 runtime dependency** for Help. → Already required on the current build's help; keep the
  same assumption; degrade to opening the guide URL if WebView2 is unavailable.
- **App size grows** with the bundled WinAppSDK runtime on top of the .NET runtime. → Accept for the
  MSI; it's a desktop app, not a download-size-critical one.
- **Scope is large.** → Land in the recommended phase order (skeleton → Settings/General → Auto-fix +
  exceptions + picker → tray flyout → feedback → onboarding → update/help), each independently shippable.

## Open Questions

_The original questions are settled: **in-place migration** (Decision 12) and packaging, which moved
to **dual MSIX + MSI** (Decision 13). `build-msi.ps1` did need reworking — WinAppSDK self-contained is
not producible here, and WiX needs `-p:Platform=x64` — both done._

Still open:

- **Will `runFullTrust` be approved?** Submitted 5 August 2026 and awaiting a manual review, for an app
  whose shape (global hook + input injection) invites scrutiny. Unknown latency; the MSI channel is
  the hedge.
- **Accurate caret position in apps with no classic caret** (Chrome, VS Code, Electron): needs UI
  Automation. The chip currently falls back to the focused window's corner there.
- **Toasts (`1g`)** — the error and remember-word notifications are specified but not built; the
  error case still only logs. The corresponding spec requirement is therefore not yet satisfied.
- **Thirteen interface languages are partly translated.** en/uk/ru are complete as of 0.2.3; the rest
  fall back to English for the ~50 strings this redesign added, and the picker says so
  (`Loc.IsComplete`) rather than leaving the user to discover it.

Settled since:

- **New UI strings were English-only** — the redesign's descriptions and prose had no translation keys,
  so choosing Ukrainian or Russian translated the tab names and left the rest of Settings and all of
  onboarding in English. Closed in 0.2.3 by routing every string through `Loc`, translating en/uk/ru,
  and making `ApplyLanguage()` the single path used at construction as well as on a language change.
- **Whether the packaged app's settings are isolated** — they are not. A full-trust MSIX reads and
  writes the same `%APPDATA%\Switcher3way` as the MSI build (verified on Windows 11 26200), so the two
  channels share settings and a user can move between them without losing anything. Nothing should rely
  on per-package isolation here.

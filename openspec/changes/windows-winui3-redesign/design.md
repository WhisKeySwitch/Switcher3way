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

1. **Unpackaged, self-contained Windows App SDK — keep the MSI + updater.** Build the WinUI 3 app
   *unpackaged* (Windows App SDK self-contained, `WindowsAppSDKSelfContained=true`,
   `WindowsPackageType=None`) so it still ships as the existing per-machine **MSI** and the SHA-256
   updater keeps working unchanged (the updater relaunches an `.exe`; the apphost stays an `.exe`).
   *Rejected:* MSIX/Store — it would replace the whole distribution + update pipeline we just built.
   Cost: the app grows (WinAppSDK runtime bundled) and unpackaged **AppNotification** needs explicit
   registration (below).

2. **Tray icon via `H.NotifyIcon.WinUI`.** NotifyIcon isn't in the SDK. Use the maintained
   `H.NotifyIcon.WinUI` package, which supports a WinUI `MenuFlyout`/custom flyout as the context
   menu — that's exactly the `1d` flyout. Keep `TrayApp.MakeFlag` icon rendering and the 400 ms
   `RefreshIcon` poll verbatim (dimmed + pause bars when `!EffectivelyEnabled`). *Rejected:* a raw
   `Shell_NotifyIcon` Win32 host — more code, and the flyout would be hand-built.

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

- **Migrate in place vs. a parallel WinUI project during transition?** Leaning parallel
  (`Switcher3way.App.WinUI`) sharing `Core`/settings/engine, cut over when at parity — keeps `main`
  shippable. To confirm with the user before implementation.
- **Do we keep the current MSI toolchain unchanged, or does unpackaged WinUI require build-script
  changes** (WindowsAppSDK runtime staging into the publish folder)? Expected: `build-msi.ps1` picks
  up the extra runtime files automatically via `dotnet publish`, but verify during the skeleton phase.

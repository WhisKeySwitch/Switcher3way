## 1. Signing + CI foundation (do first — unsigned won't launch on managed devices)

- [ ] 1.1 Apply to the **SignPath Foundation** OSS program for Switcher3way (MIT + public repo); record the organization id, project slug, and signing-policy slug
- [x] 1.2 Scaffold the production Windows solution (`windows/Switcher3way.slnx` — `Switcher3way.Core` lib + `Switcher3way.Core.Tests` xunit). App-shell exe project (`UseAppHost=true`) deferred to phase 6/M6 (WPF vs WinForms). SignPath/CI tasks (1.1, 1.3–1.5) remain deferred to post-traction.
- [ ] 1.3 Add a GitHub Actions workflow: `dotnet publish` → upload artifact → `signpath/github-action-submit-signing-request` → download signed artifact; store `SIGNPATH_API_TOKEN` as a CI secret
- [ ] 1.4 Sign **both** the executable and the installer, RFC-3161 **timestamped**; `signtool verify /pa` in CI to gate the build
- [ ] 1.5 Confirm the release-signed artifact runs cleanly on a **clean/managed Windows machine** with no SmartScreen block. (Dev-machine launch is already unblocked — the original block was a managed ASR "block low-prevalence executables" rule, since disabled/unenrolled; dev builds run unsigned or via the `dotnet` host, optionally signed with the self-signed dev identity in `signing/README-windows.md`.)

## 2. Portable detection core (C#, no Win32)

- [x] 2.1 Port `NWayResolver.resolve`/`manualPlan`, `LayoutDetector.passesSoftGates` + letter-core trimming into a UI/OS-free assembly (`Switcher3way.Core`); the OS bindings (dictionary, layout enumeration/render) and always-convert list are behind interfaces (`IDictionaryValidator`, `ILayoutCatalog`, `IAlwaysConvertList`). Remaining `AutoSwitchPolicy` bits (denied-apps / secure-input / remote) are orchestrator/platform concerns → phase 5.3.
- [x] 2.2 Unit-test the core against the macOS behavior — **27 xunit tests green**: single winner, uk↔ru ambiguity left alone, valid-in-current, always-convert override, punctuation re-render (`db,fxnt`→`вибачте`), 2-letter minimum, all-caps/camelCase/mixed-alphabet gates, letter-core trimming, manual cycle order + dedup + remote-forwarded bail-out.

## 3. Offline dictionaries (Hunspell)

- [x] 3.1 Integrate Hunspell (`WeCantSpell.Hunspell`, managed — no native deps) AND bundle real en/ru/uk dictionaries (`dict/`): en `MIT AND BSD` (SCOWL), ru `BSD-3` (Lebedev), uk **`MPL 1.1`** (LibreOffice `uk_UA` — the NonCommercial `dict_uk` was rejected). Loaded via `HunspellDictionaryValidator`; each dict's license ships alongside. See `windows/src/Switcher3way.Dictionaries/DICTIONARIES.md`.
- [ ] 3.2 Validate dictionary quality against the macOS `NSSpellChecker` baseline on a representative word set (punctuation-attached and 2-letter cases included) — real dicts now bundled + smoke-tested (hello/привет/привіт); the Mac-captured baseline comparison is still to do (see DICTIONARIES.md)
- [x] 3.3 Wire validation behind the letter-core validator interface the detection core expects — `HunspellDictionaryValidator : IDictionaryValidator`; end-to-end test plugs it into `NWayResolver` (real Hunspell check of привет/вибачте). 37 tests green.

## 4. Live detection loop (graduate the spike's proven patterns)

- [x] 4.1 Graduated the spike's Win32 patterns into `windows/src/Switcher3way.App/`: `Win32LayoutCatalog` (`GetKeyboardLayoutList` enumeration + dead-key-safe `ToUnicodeEx` render, implementing Core `ILayoutCatalog`), `KeyClassifier`, `KeyboardMonitor` (`WH_KEYBOARD_LL` hook, `LLKHF_INJECTED`-ignoring, word buffer), `LayoutSwitcher` (switch + confirm + `AttachThreadInput` fallback), `TextRewriter` (release-wait/per-char `SendInput` + UIPI detect).
- [x] 4.2 Auto path assembled in `Engine` (hook → boundary → `NWayResolver.Resolve` over Win32 renders + Hunspell → `SwitchForeground` + `Rewrite`, off the hook thread). **Operator-verified live**: real typing in Notepad auto-fixed many words correctly (ghbdsn→привіт, руддщ→hello, Цщкдв→World, Plhfdcndeqnt?→Здравствуйте,, …), left ambiguous (собака, valid uk+ru) and already-valid words alone, and preserved capitals/punctuation. Added a no-op guard: when the target render equals the original (identical-looking Cyrillic across uk/ru), switch the layout but skip the needless rewrite.
- [x] 4.3 Manual trigger (F9, laptop-safe, swallowed) + N-way cycle via `NWayResolver.ManualPlan` (…→ru→uk→original), single-shot + re-entrancy guard. **Buffer-reset guard added** after an operator found F9 deleting selected text: a `WH_MOUSE_LL` hook clears the word buffer on any click, and a foreground-window check drops a stale buffer on focus change (implements the spec's "reset on mouse/app-switch" so F9 can't backspace over a selection). Live cycle still needs an operator run.
- [x] 4.4 Removed the throwaway `windows-spike/` code (patterns graduated); kept `windows-spike/FINDINGS.md` as the record with a graduation note.

## 5. Parity features

- [x] 5.1 Tray UI (`TrayApp`, WinForms `NotifyIcon`): status header, **Enabled** + **Auto-fix** toggles, **Pause** submenu (30 min / 1 h / until restart / resume), **Quit**; icon + tooltip reflect on/off/paused; a 30 s timer resumes a timed pause visually. `Engine` now gates auto on `EffectivelyEnabled && AutoFix` and manual (F9) on `EffectivelyEnabled`. (App runs as a tray app; End is a normal key again — no console-quit.)
- [x] 5.2 Settings persistence (`SettingsManager` → `%AppData%\Switcher3way\settings.json`) + a **tabbed settings window** (`SettingsForm`, System-Settings style like macOS: General / Auto-fix / Advanced / About) with grouped controls, a manual trigger-key selector, a "start at login" toggle, and a **unified searchable exceptions manager** (Apps / Never / Always with a live count; password managers shown "always off" + non-removable).
- [~] 5.3 Exceptions: **denied-apps** list (with defaults — password managers, terminals, RDP), **never-convert** / **always-convert** word lists — all persisted in `SettingsManager` and enforced in `Engine` (denied-app gate on auto AND manual; never-convert on auto; always-convert via Core `IAlwaysConvertList`), and **editable in the settings window**. **Password-field detection via UI Automation** (`SecureField`, `IsPassword`) now gates auto + manual — covers in-browser login fields the denied-apps list can't.
- [x] 5.4 Per-app layout memory: a `SetWinEventHook(EVENT_SYSTEM_FOREGROUND)` foreground watcher remembers each app's last-used layout (by exe) and restores it on focus return; gated on `EffectivelyEnabled` + a `PerAppMemory` setting with a tray toggle. Foreground change also clears the word buffer (app-switch safety).
- [ ] 5.5 Interface localization parity (reuse the existing string set where possible)
- [x] 5.6 Diagnostics: opt-in rotating file log (`Diagnostics`, `%AppData%\Switcher3way\Logs\switcher3way.log`, 5 MB cap + one backup), off by default, with tray **Debug log** toggle + **Open log folder**. App is now **`WinExe`** (no console window); the self-test attaches to the parent console (`AttachConsole`). Engine conversion trace routed to the log (mirrors macOS `rslog`).
- [x] 5.7 Elevated-window handling (R2): when the rewrite's `SendInput` is refused/short (`Protected`/`Partial` — a higher-integrity target), the Engine raises a throttled (30 s) notification and the tray shows a balloon ("can't change text in this window — it may be running as administrator") instead of failing silently. (Optional elevated *mode* deferred.)

## 6. Packaging, distribution, docs

- [ ] 6.1 Choose the shell framework (WPF/WinForms/WinUI) and installer format (MSIX vs WiX MSI); record the decision (MSIX signing must match the SignPath cert's publisher)
- [ ] 6.2 Produce the signed, timestamped installer via the phase-1 pipeline; publish alongside the existing macOS GitHub release flow
- [ ] 6.3 Document the Windows build + SignPath signing loop in `CLAUDE.md` / `NOTES-3WAY.md`, and the SmartScreen reputation path for first-run users

## 7. Validation and sign-off

- [ ] 7.1 Manually verify EN↔RU and EN↔UK auto + manual conversion across Win32, UWP, and Electron target apps
- [ ] 7.2 Verify exclusions (denied apps, password fields, elevated windows) behave per spec
- [ ] 7.3 Confirm fully-offline operation and that the signed exe launches on an EDR-managed device

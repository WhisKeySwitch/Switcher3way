## 1. Signing + CI foundation (do first — unsigned won't launch on managed devices)

- [ ] 1.1 Apply to the **SignPath Foundation** OSS program for Switcher3way (MIT + public repo); record the organization id, project slug, and signing-policy slug
- [ ] 1.2 Scaffold the production Windows solution (`windows/`), a C#/.NET app with `UseAppHost=true` so a real apphost `.exe` is produced (unlike the spike's `UseAppHost=false`)
- [ ] 1.3 Add a GitHub Actions workflow: `dotnet publish` → upload artifact → `signpath/github-action-submit-signing-request` → download signed artifact; store `SIGNPATH_API_TOKEN` as a CI secret
- [ ] 1.4 Sign **both** the executable and the installer, RFC-3161 **timestamped**; `signtool verify /pa` in CI to gate the build
- [ ] 1.5 Confirm the release-signed artifact runs cleanly on a **clean/managed Windows machine** with no SmartScreen block. (Dev-machine launch is already unblocked — the original block was a managed ASR "block low-prevalence executables" rule, since disabled/unenrolled; dev builds run unsigned or via the `dotnet` host, optionally signed with the self-signed dev identity in `signing/README-windows.md`.)

## 2. Portable detection core (C#, no Win32)

- [ ] 2.1 Port `NWayResolver.resolve`/`manualPlan`, `LayoutDetector.passesSoftGates` + letter-core trimming, and `AutoSwitchPolicy` (exceptions/pause/per-app/secure-context) into a UI/OS-free assembly
- [ ] 2.2 Unit-test the core against the macOS behavior: single unambiguous winner, ambiguity left alone (e.g. `там`), letter-core trimming, punctuation re-render, 2-letter minimum, code-like gates

## 3. Offline dictionaries (Hunspell)

- [ ] 3.1 Integrate Hunspell into the app and bundle en/uk/ru dictionaries
- [ ] 3.2 Validate dictionary quality against the macOS `NSSpellChecker` baseline on a representative word set (punctuation-attached and 2-letter cases included)
- [ ] 3.3 Wire validation behind the letter-core validator interface the detection core expects

## 4. Live detection loop (graduate the spike's proven patterns)

- [ ] 4.1 Lift from `windows-spike/` into the production app: dead-key-safe `ToUnicodeEx` renderer, `GetKeyboardLayoutList` enumeration, `KeyClassifier` (letters+digits+OEM buffer; boundary; backspace-pop; reset), foreground switch with confirm + `AttachThreadInput` fallback, `LLKHF_INJECTED`-ignoring hook, and the release-wait/per-char `SendInput` rewrite
- [ ] 4.2 Assemble the auto path: hook → boundary → render all layouts → validate (core + Hunspell) → switch + rewrite
- [ ] 4.3 Implement the manual trigger: convert-on-demand + the N-way candidate cycle (…→ru→uk→original); pick a default trigger key present on laptops (spike showed Pause/Break is often absent; F9 worked)
- [ ] 4.4 Delete the throwaway `windows-spike/` once its patterns have graduated

## 5. Parity features

- [ ] 5.1 Tray UI: status (enabled/paused), enable/disable, auto-fix toggle, pause, open settings, quit
- [ ] 5.2 Settings window (trigger config, auto-fix, feature toggles) persisted to per-user storage
- [ ] 5.3 Exceptions: denied-apps list, never-convert / always-convert word lists, secure/password-field detection via UI Automation
- [ ] 5.4 Per-app layout memory
- [ ] 5.5 Interface localization parity (reuse the existing string set where possible)
- [ ] 5.6 Diagnostics/debug log equivalent to the macOS `rslog` decision trace
- [ ] 5.7 Elevated-window handling (R2): surface "can't act in this window" rather than silently failing; optionally offer an elevated mode

## 6. Packaging, distribution, docs

- [ ] 6.1 Choose the shell framework (WPF/WinForms/WinUI) and installer format (MSIX vs WiX MSI); record the decision (MSIX signing must match the SignPath cert's publisher)
- [ ] 6.2 Produce the signed, timestamped installer via the phase-1 pipeline; publish alongside the existing macOS GitHub release flow
- [ ] 6.3 Document the Windows build + SignPath signing loop in `CLAUDE.md` / `NOTES-3WAY.md`, and the SmartScreen reputation path for first-run users

## 7. Validation and sign-off

- [ ] 7.1 Manually verify EN↔RU and EN↔UK auto + manual conversion across Win32, UWP, and Electron target apps
- [ ] 7.2 Verify exclusions (denied apps, password fields, elevated windows) behave per spec
- [ ] 7.3 Confirm fully-offline operation and that the signed exe launches on an EDR-managed device

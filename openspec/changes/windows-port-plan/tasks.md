## 1. Portable core identification

- [ ] 1.1 Catalog the platform-independent logic in the macOS app (`NWayResolver.resolve`/`manualPlan`, `LayoutDetector.passesSoftGates` + letter-core trimming, `AutoSwitchPolicy` exception/pause/per-app rules, word-boundary buffering) and document its inputs/outputs
- [ ] 1.2 Define the language-neutral contract the Windows shell must provide to that logic (keystroke stream, per-layout renderer, dictionary validator, layout enumerator/switcher, text-rewriter, foreground-app + secure-context probes)
- [ ] 1.3 Decide reuse strategy: re-port the logic to C# vs. extract a shared native core (record decision; default is re-port for the MVP)

## 2. Win32 plumbing spike

- [ ] 2.1 Prototype a `WH_KEYBOARD_LL` hook that buffers keystrokes off the hook thread and detects word boundaries
- [ ] 2.2 Prototype per-layout rendering with `ToUnicodeEx`/`MapVirtualKeyEx` and verify the dead-key flush pattern does not corrupt live typing
- [ ] 2.3 Prototype layout enumeration (`GetKeyboardLayoutList`) and foreground-app layout switching (`WM_INPUTLANGCHANGEREQUEST`, with `AttachThreadInput` fallback)
- [ ] 2.4 Prototype text rewrite via `SendInput` (`KEYEVENTF_UNICODE`) with a clipboard fallback, and confirm the elevated-window (UIPI) limitation is detectable

## 3. Dictionary integration

- [ ] 3.1 Integrate Hunspell into the C# app and load bundled en/uk/ru dictionaries
- [ ] 3.2 Validate dictionary quality against the macOS `NSSpellChecker` baseline on a representative word set (including punctuation-attached and 2-letter cases)
- [ ] 3.3 Wire validation behind the same letter-core interface the detection logic expects

## 4. MVP detection loop

- [ ] 4.1 Port the N-way resolver and soft gates to C# and unit-test them against the macOS behavior (single-winner, ambiguity, letter core, punctuation re-render, 2-letter minimum)
- [ ] 4.2 Assemble the live auto path: hook → boundary → render-all-layouts → validate → switch + rewrite
- [ ] 4.3 Implement the manual trigger: convert-on-demand, candidate cycling, and restore-original-and-layout
- [ ] 4.4 Add a minimal tray icon with enable/disable, auto-fix toggle, pause, and quit

## 5. Parity features

- [ ] 5.1 Settings window (trigger config, auto-fix, feature toggles) persisted to per-user storage
- [ ] 5.2 Exception management: denied-apps list, never-convert / always-convert word lists, and secure/password-context detection via UI Automation
- [ ] 5.3 Per-app layout memory
- [ ] 5.4 Interface localization parity (reuse the existing string set where possible)
- [ ] 5.5 Diagnostics/debug log equivalent to the macOS `rslog` decision trace

## 6. Packaging, signing, and distribution

- [ ] 6.1 Choose shell framework (WinForms/WPF/WinUI) and installer format (MSIX vs. WiX MSI); record the decision
- [ ] 6.2 Authenticode-sign the binaries and installer
- [ ] 6.3 Produce a signed installer artifact and document the SmartScreen "Run anyway" path and AV transparency (VirusTotal)
- [ ] 6.4 Publish the Windows artifact alongside the existing GitHub release flow

## 7. Validation and sign-off

- [ ] 7.1 Manually verify EN↔RU and EN↔UK auto + manual conversion across Win32, UWP, and Electron target apps
- [ ] 7.2 Verify exclusions (denied apps, password fields, elevated windows) behave per spec
- [ ] 7.3 Confirm fully-offline operation and resolve the design's open questions (min Windows version, shared-core decision, trigger default)

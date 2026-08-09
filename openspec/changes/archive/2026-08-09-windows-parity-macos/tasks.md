## 1. Password-field guard (ships first — see design D7)

- [x] 1.1 Add `SecureFieldDetector.swift`: fetch the focused AX element once
      (`AXUIElementCreateApplication` → `kAXFocusedUIElementAttribute`) with
      `AXUIElementSetMessagingTimeout(axApp, 0.05)`; return a verdict struct carrying the overall
      answer plus each signal's individual result
- [x] 1.2 Implement signal 1: `kAXSubroleAttribute == "AXSecureTextField"`
- [x] 1.3 Implement signal 2: text-entry role (`AXTextField`/`AXTextArea`/`AXComboBox`/`AXSearchField`)
      **and** password wording in `kAXTitleAttribute`, `kAXDescriptionAttribute`,
      `kAXPlaceholderValueAttribute`, `kAXHelpAttribute`, or the title of `kAXTitleUIElementAttribute`
- [x] 1.4 Port the multilingual word list from `windows/src/Switcher3way.App/SecureField.cs`
      (`password`, `passwd`, `passcode`, `пароль`, `passwort`, `mot de passe`, `contraseña`, `senha`,
      `hasło`, `密码`, `パスワード`, `비밀번호`), matched case-insensitively
- [x] 1.5 Fold in signal 3 (`IsSecureEventInputEnabled()`) so the detector is the single verdict source;
      make every failure path catch, log, and return not-a-password
- [x] 1.6 Memoize the verdict per focused element with a short TTL; invalidate on app switch and on the
      `KeyboardMonitor` buffer-reset events
- [x] 1.7 Replace `AutoSwitchPolicy.secureInputActive` at its `handleAutoConvert()` call site with the
      detector verdict; keep the phrase-tracker reset on suppression
- [x] 1.8 Gate the manual trigger paths (`onAltTap`, `onAltReconvert`) on the same verdict *before*
      any selection read, so the clipboard fallback never touches a password field
- [x] 1.9 Add `logAlways(_:)` beside `rslog` in `KeyboardMonitor.swift` — writes regardless of the
      debug-log setting, same rotation and queue
- [x] 1.10 Log the per-word guard line (verdict + each signal + focused-element identification) on every
      evaluated word when debug logging is on, and an explicit suppression line when it fires
- [x] 1.11 Add a `diagpw` command-line mode to `main.swift` that prints the same breakdown for whatever
      currently has focus
- [x] 1.12 Verify on the **installed, signed** app (not a debug build): a masked browser password field,
      a field revealed by a show/hide toggle, a native `NSSecureTextField`, and an ordinary text field —
      confirm each signal's result in the log and that no conversion occurs in the first three

## 2. Package split and test target

- [x] 2.1 Add `DictionaryValidating` and `LayoutCatalog` protocols (mirroring the Windows
      `IDictionaryValidator` / `ILayoutCatalog`) plus an injectable log sink
- [x] 2.2 Restructure `Package.swift` into `Switcher3wCore` (library, Foundation only), `Switcher3w`
      (executable, depends on core), and `Switcher3wCoreTests`
- [x] 2.3 Move `passesSoftGates` + `letterCore`, `NWayResolver.evaluate`/`manualPlan`, `PhraseTracker`,
      and exception-list matching into the core — mechanical move, no behavior edits
- [x] 2.4 Make `Dict`, `LayoutSwitcher` and `DynamicKeyMapping` conform to the new protocols in the
      executable target; wire the log sink to `rslog`
- [x] 2.5 Confirm `bash build_app.sh` still produces a signed bundle that launches with permissions
      intact, before anything is built on the new structure
- [x] 2.6 Add test doubles (fake dictionary, fake layout catalog) modelled on
      `windows/tests/Switcher3way.Core.Tests/Fakes.cs`
- [x] 2.7 Soft-gate tests: length, all-caps, mixed-script, code-identifier, Caps Lock exemption,
      letter-core trimming of edge punctuation
- [x] 2.8 `evaluate` tests: keep / convert / ambiguous outcomes, always-convert override,
      never-convert suppression
- [x] 2.9 Ambiguity tests: preference language, "off", and phrase-lock precedence over the preference
- [x] 2.10 `PhraseTracker` tests: correction building, contradictory-phrase refusal, hard-boundary reset,
      max correction length
- [x] 2.11 Dictionary-quality test against a checked-in en/uk/ru word fixture, reporting per-language
      pass rate with a recorded threshold and an explicit skip when a system dictionary is absent
- [x] 2.12 Confirm `swift test` passes from a clean checkout with no app installed and no permissions

## 3. Notifications

- [x] 3.1 Add `ConversionNotifier.swift`: lazy `UNUserNotificationCenter` authorization, guarded on
      `Bundle.main.bundleIdentifier != nil` so non-bundled `swift run` never traps
- [x] 3.2 Register the notification category with a "Never convert this" action; adopt
      `UNUserNotificationCenterDelegate` on `AppDelegate` and handle activation from `userInfo`
- [x] 3.3 Error notification for a rewrite that could not be applied, throttled at 30 s; wire it to the
      failure paths of `beginCycle`/`cycleStep`/`convertViaClipboard`
- [x] 3.4 Replace the modal `NSAlert` in `offerExceptionAfterUndo()` with the notification offer,
      keeping the 8 s window, the once-per-session rule, and the already-excepted check
- [x] 3.5 Route the accepted action into `SettingsManager.deniedWords` and confirm the exceptions list
      reflects it live
- [x] 3.6 Log registration, authorization denial, and delivery failure through `logAlways`
- [x] 3.7 Verify: denied notification permission leaves conversion fully working; a failed rewrite
      notifies once, not per word

## 4. Conversion feedback chip

- [x] 4.1 Move the trigger key→label mapping out of `SettingsWindowController.populateTriggerPopup`
      into `L10n` so the popup and the chip read one source
- [x] 4.2 Replace `CaretIndicator`'s flag `NSTextField` with an attributed-string label: typed form with
      `.strikethroughStyle`, arrow, converted form, trigger keycap; size the panel to the content
- [x] 4.3 Add `showConversion(original:converted:)` alongside `layoutChanged()`, with the existing
      fade/hold/fade timing
- [x] 4.4 Anchor to the AX caret, falling back to the focused window when the caret is unresolvable, and
      skipping only when neither resolves
- [x] 4.5 Call it from the auto-conversion, phrase-correction and manual-cycle success paths; suppress it
      on the final restore-to-original step
- [x] 4.6 Add the `com.switcher3w.conversionChip` setting (default on) and its Settings switch; keep the
      panel alive when either the chip or the beta flag badge is enabled
- [x] 4.7 Apply the password verdict, denied-apps and remote-client suppression to the chip
- [x] 4.8 Add the new en/uk/ru strings to `Localization.swift`; confirm the other 13 languages fall back
      to English cleanly

## 5. Documentation and close-out

- [x] 5.1 Update `docs/user-guide.md`, `.uk.md`, `.ru.md`: password-field behavior, the chip and its
      toggle, the notification actions, and the never-logged-keystrokes guarantee
- [x] 5.2 Update the architecture map in `CLAUDE.md` with the new files and the target split; document
      `swift test` and `diagpw` in the Debugging section
- [x] 5.3 Update `openspec/CAPABILITIES.md` with the three new capabilities
- [x] 5.4 Full loop on a clean machine state: `bash build_app.sh` → install → grant → verify the guard,
      the chip, both notifications, and `swift test` green
- [x] 5.5 Run `openspec validate windows-parity-macos --strict` and archive the change

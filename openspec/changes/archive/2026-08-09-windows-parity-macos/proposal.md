## Why

The Windows port (`windows/`, shipped 0.2.0 → 0.2.5) has since gained four things the macOS app never
had. One of them is a security fix: Windows 0.2.4/0.2.5 shipped after a user reported that
auto-conversion **rewrote text inside a login form**, and the fix was a focused-element password guard
with four independent signals. macOS today has a single global check —
`IsSecureEventInputEnabled()` ([AutoSwitch.swift:89](../../../Sources/Switcher3w/AutoSwitch.swift#L89)) —
which has exactly the blind spot Windows found: a field that is *labelled* a password but not masked
(any "show password" toggle), a web form that masks in JavaScript, or an Electron host that never asks
for secure event input. In all three the macOS app will happily retype what the user typed.

The other three are quality-of-life gaps that Windows closed and macOS did not: conversion happens with
no visible feedback about *what* was changed, a rewrite that fails is silent, the learn-from-undo prompt
is a **blocking modal alert** in the middle of typing, and the detection core — the part that decides
whether to touch the user's text at all — has no automated tests on macOS while the Windows port has a
full xunit suite over the same algorithm.

## What Changes

- **Password-field guard beyond secure input.** A new focused-element check, modelled on
  `windows/src/Switcher3way.App/SecureField.cs`, gates auto-conversion, the manual trigger, and the
  caret feedback. It layers on top of the existing `IsSecureEventInputEnabled()` check rather than
  replacing it. Signals, in order: the focused element's Accessibility subrole is
  `AXSecureTextField`; the element's role/title/placeholder/description contains password wording in
  any of the languages this app's users meet (the Windows list: `password`, `пароль`, `passwort`,
  `mot de passe`, `contraseña`, `senha`, `hasło`, `密码`, `パスワード`, `비밀번호`, …). Any positive
  signal suppresses conversion; any query failure logs and returns "not a password" — it can never
  block or crash the conversion path. Deliberately over-blocks: a false positive costs one unfixed
  word in a box labelled *password*, a false negative rewrites a credential.
- **A diagnostic that shows what the guard saw.** A `Describe()`-equivalent line (which signal
  answered, what element had focus) logged on every evaluated word when debug logging is on, plus a
  command-line diagnostic mode. On Windows the guard silently never fired for four releases precisely
  because "no suppression" and "guard broken" were indistinguishable in the log.
- **Conversion feedback chip.** The caret badge grows from a bare flag emoji into the Windows chip: the
  typed form struck through, an arrow, the converted form, and the trigger keycap as an undo hint
  (`ghbdsn → привіт  ⌥ to undo`). It fires on a **conversion**, not only on a layout change, and
  reuses the existing non-activating click-through panel and Accessibility caret resolution.
- **Non-blocking actionable notifications.** `UNUserNotificationCenter` replaces the modal `NSAlert`
  for learn-from-undo, carrying a "Never convert this" action button; and a new, throttled error
  notification tells the user when a rewrite could not be applied at all — today that failure is
  entirely silent.
- **A test target for the detection core.** The platform-independent decision logic (soft gates,
  letter-core trimming, N-way `evaluate`, `PhraseTracker`, exception-list matching) is made reachable
  from tests, and gains a suite mirroring the Windows one — including a dictionary-quality test that
  measures the validator against a checked-in word fixture. **BREAKING (build):** the SwiftPM package
  gains a library target and a test target; `Sources/Switcher3w/` is split so the executable depends
  on the library.
- **Always-on logging for critical failures.** A `logAlways` path for failures a user could otherwise
  never report (the Accessibility API refusing, notification registration failing), independent of the
  debug-log toggle.

## Capabilities

### New Capabilities
- `password-field-protection`: detecting that the focused control is a password field by inspecting the
  Accessibility element, and suppressing every text-touching path when it is — independent of, and in
  addition to, the process-global secure-input flag.
- `conversion-notifications`: non-blocking user notifications for the two things the app cannot say any
  other way — a rewrite it could not perform, and an offer to remember a word after the user undoes a
  conversion — with actions handled without stealing focus.
- `detection-core-testability`: the decision logic is importable by a test target and covered by an
  automated suite, including measured dictionary quality against a fixture.

### Modified Capabilities
- `layout-change-feedback`: the caret badge SHALL be able to show the conversion itself (original →
  converted plus an undo hint) and SHALL fire on conversion, not only on layout change; its
  suppression rules extend to the new password-field guard.
- `automatic-conversion-on-word-boundaries`: the secure-context gate SHALL additionally consult the
  focused-element password check, not only `IsSecureEventInputEnabled()`.
- `manual-conversion-and-undo`: the same password gate SHALL apply to the manual trigger; the
  learn-from-undo offer SHALL be a non-blocking notification rather than a modal alert.
- `diagnostics-and-debug-logging`: adds an always-on channel for critical failures, and requires that
  the password-guard verdict be logged per evaluated word so a broken guard is distinguishable from an
  idle one.

## Impact

- **Code.** New: `SecureFieldDetector.swift`, `ConversionNotifier.swift`, `Tests/`. Modified:
  `AutoSwitch.swift` (policy gate), `AppDelegate.swift` (auto + trigger paths, learn-from-undo),
  `CaretIndicator.swift` (chip content and trigger), `KeyboardMonitor.swift` (`logAlways`),
  `SettingsWindowController.swift` + `SettingsManager.swift` (chip toggle), `Localization.swift`
  (new strings × 16 languages), `Package.swift` (library + test targets).
- **Build.** `Package.swift` restructured into `Switcher3wCore` (library) + `Switcher3w` (executable) +
  `Switcher3wCoreTests`; `build_app.sh` unaffected in behavior but builds the new graph. `swift test`
  becomes a real command in this repo for the first time.
- **Permissions.** No new TCC grants — the focused-element check uses the Accessibility permission the
  app already requires. Notifications need `UNUserNotificationCenter` authorization, requested lazily
  and treated as optional: a denial degrades to logging, never to a broken conversion path.
- **Risk.** The password guard runs on every evaluated word; a slow Accessibility query would stall the
  conversion path, so it must be bounded by a timeout and cached per focused element (the caret
  indicator already carries the pattern for both).
- **Docs.** `docs/user-guide*.md` (all three languages) gain the password-field behavior, the chip, and
  the notification actions; `CLAUDE.md` architecture map and `openspec/CAPABILITIES.md` updated.

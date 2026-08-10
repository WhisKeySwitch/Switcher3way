## Context

See `proposal.md — Why` for motivation. The design-relevant state of the macOS app:

- The only secure-context gate is `AutoSwitchPolicy.secureInputActive`
  ([AutoSwitch.swift:89](../../../Sources/Switcher3w/AutoSwitch.swift#L89)), a one-line wrapper over
  `IsSecureEventInputEnabled()`. It is consulted once, in `handleAutoConvert()`
  ([AppDelegate.swift:373](../../../Sources/Switcher3w/AppDelegate.swift#L373)); the manual trigger
  path does not consult it at all.
- Focused-element Accessibility inspection already exists twice, with the patterns this change needs:
  `TextConverter.isFocusedElementEditable()`
  ([TextConverter.swift:50](../../../Sources/Switcher3w/TextConverter.swift#L50)) fetches
  `kAXFocusedUIElementAttribute` and reads `kAXRoleAttribute`; `CaretIndicator` bounds its queries with
  `AXUIElementSetMessagingTimeout(axApp, 0.25)`
  ([CaretIndicator.swift:145](../../../Sources/Switcher3w/CaretIndicator.swift#L145)). No new
  permission is required — Accessibility is already mandatory for the app to function at all.
- `CaretIndicator` is a `NSPanel` with a single `NSTextField` holding a flag emoji, driven by
  `layoutChanged()` from `updateStatusIcon()`
  ([AppDelegate.swift:730](../../../Sources/Switcher3w/AppDelegate.swift#L730)) — i.e. by *layout
  change*, not by conversion. It is created only when its beta setting is on.
- Learn-from-undo exists as `offerExceptionAfterUndo()`
  ([AppDelegate.swift:116](../../../Sources/Switcher3w/AppDelegate.swift#L116)) and runs a **modal**
  `NSAlert` mid-typing. There is no user-visible signal of any kind when a rewrite fails.
- The detection core is not separable today: `NWayResolver.evaluate` calls `LayoutSwitcher`
  (Carbon TIS), `Dict` (NSSpellChecker) and `rslog` as concrete globals, and is `@MainActor`. The
  package has one executable target and no test target.
- The Windows port has already solved all four problems against the same algorithm, so its structure is
  available as a reference rather than a thing to invent: `SecureField.cs`, `CaretChip.cs`, `Toast.cs`,
  `Switcher3way.Core` + `Switcher3way.Core.Tests`.

## Goals / Non-Goals

**Goals:**
- One password verdict, computed once per evaluated word, consumed by the auto path, the manual path
  and the feedback surface — not three independent checks that can drift apart.
- The password guard ships without waiting for the package restructure, so the security gap closes
  first.
- The detection algorithm is not rewritten by the test work. The extraction is mechanical; behavior
  changes are a separate concern from making it testable.
- Every new subsystem degrades to "logged and ignored" on failure. None of them may add a way for the
  conversion path to break.

**Non-Goals:**
- Sharing code between the macOS and Windows implementations. They stay parallel ports (the decision
  from `2026-07-20-windows-port-plan` D1); Windows is a reference for *structure*, not a dependency.
- Porting the remaining minor Windows deltas (drag-drop exceptions, running-app picker, failed-update
  tracking). They are listed in the parity sweep but deliberately out of this change.
- Reworking the existing beta caret-flag feature or its setting. The chip is additive.
- 16-language translation of the new strings by hand — see the localization decision below.

## Decisions

### D1 — Password detection reads the focused Accessibility element, not a new permission

`AXUIElementCreateApplication(frontmost.pid)` → `kAXFocusedUIElementAttribute` → three reads on the
element:

1. `kAXSubroleAttribute == "AXSecureTextField"` — the canonical macOS answer, and what AppKit's
   `NSSecureTextField` and WebKit's masked `<input type="password">` publish.
2. role in the text-entry set (`AXTextField`, `AXTextArea`, `AXComboBox`, `AXSearchField`) **and**
   password wording in any of `kAXTitleAttribute`, `kAXDescriptionAttribute`,
   `kAXPlaceholderValueAttribute`, `kAXHelpAttribute`, or the title of `kAXTitleUIElementAttribute`.
3. the existing `IsSecureEventInputEnabled()`, retained unchanged as a third signal.

*Why not secure-input alone (status quo):* it is process-global and advisory. An unmasked "show
password" field, a form that masks in JavaScript, and Electron hosts that never call
`EnableSecureEventInput` all leave it clear — which is the precise set of cases the Windows port
found in the field.

*Why the wording heuristic at all:* signal 1 reports *masking*, not *intent* — exactly the finding
that forced Windows 0.2.5 after 0.2.4's `IsPassword`-only guard shipped incomplete. Any form with a
reveal toggle turns its input into plain text while revealed. The word list is copied from
`SecureField.PasswordWords` and matched case-insensitively against the label the *page* supplies, so it
is keyed to the languages users meet on login forms, not to the app's interface language.

*Asymmetric error cost, deliberately:* a false positive costs one unfixed word inside a box labelled
"password"; a false negative rewrites a credential. Over-blocking is the correct bias.

### D2 — One verdict per word, cached by focused element

The verdict is computed once at the top of the auto path and the manual path and passed down, rather
than being re-queried by the chip. It is memoized in a small cache keyed by the focused element,
invalidated on the events the app already tracks as focus/context changes (app switch, the
`KeyboardMonitor` buffer-reset events) and by a short TTL as a backstop.

*Why:* the guard runs on every word boundary, and an AX round-trip to an unresponsive app is the one
way this change could make typing feel slow. Messaging timeout is set to **0.05 s** for this path —
tighter than `CaretIndicator`'s 0.25 s, because that one runs after a switch while this one sits in
front of the user's next keystroke. On timeout: not-a-password, logged.

*Alternative rejected:* observing `kAXFocusedUIElementChangedNotification` for exact invalidation. It
needs a per-application observer and a run-loop source per app the user touches, for a cache whose
staleness window is already one word.

### D3 — The manual trigger gets the same gate, despite being explicit

The trigger deliberately acts where auto declines (that is a shipped requirement in
`manual-conversion-and-undo`), so gating it needs justifying: the user pressing a key does not make it
safe to *read* a password field through the clipboard fallback, nor to retype its contents. Windows
made the same call (`ManualStep` checks `SecureField.IsFocusedPassword()` before anything else).

### D4 — The chip extends `CaretIndicator` rather than becoming a second panel

The panel already solves the hard parts: non-activating, click-through, all-Spaces, never steals focus,
AX caret resolution with the Chromium text-marker fallback. The change is content and trigger:
the single flag `NSTextField` becomes an `NSAttributedString` (typed form with
`.strikethroughStyle`, an arrow, converted form, then the trigger keycap), and a new
`showConversion(original:converted:)` entry point is called from the conversion sites in
`AppDelegate` and `TextConverter`'s success callbacks.

The trigger keycap names the *configured* trigger. `SettingsWindowController.populateTriggerPopup`
already owns the key→title mapping; that mapping moves to `L10n` so both the popup and the chip read
it from one place (Windows solved this with `SettingsManager.TriggerLabel`).

**New setting** `com.switcher3w.conversionChip`, default **on**, separate from the existing beta
caret-flag toggle. *Why default on:* the whole point is that conversions are currently invisible; and
unlike the flag badge, the chip has a defined fallback (window anchor) when the caret is unresolvable,
so it does not silently do nothing on Electron hosts. The two features share the panel but not the
setting, so enabling the chip does not turn on the beta flag badge.

### D5 — `UNUserNotificationCenter`, requested lazily, never load-bearing

Error notifications are throttled at 30 s (matching Windows' `NotifyProtected`). The remember-word
offer carries a `UNNotificationAction` in a registered category; the word travels in `userInfo`, and
`AppDelegate` adopts `UNUserNotificationCenterDelegate` to handle activation.

*Why not keep `NSAlert`:* it is modal and takes focus, in the middle of typing, immediately after the
app already interrupted the user by rewriting their word. It is the single worst place in the app for a
blocking dialog.

*Why not `NSUserNotification`:* deprecated since 10.14 and unavailable on the deployment target's
modern SDK path.

**Gotcha to design around:** `UNUserNotificationCenter.current()` traps in a process with no bundle
identifier — which is exactly how the package runs under `swift run` / a plain SwiftPM build. Every
entry point is guarded on `Bundle.main.bundleIdentifier != nil` and falls back to logging, so the
non-bundled developer loop keeps working. Authorization is requested on first use, not at launch; a
denial is logged once via the always-on channel and the app carries on.

### D6 — Package split mirrors the Windows Core boundary

`Package.swift` gains:

- `Switcher3wCore` (library) — `passesSoftGates` + `letterCore`, `NWayResolver.evaluate`/`manualPlan`,
  `PhraseTracker`, exception-list matching. Depends on Foundation only.
- `Switcher3w` (executable) — everything AppKit/Carbon, plus the production adapters.
- `Switcher3wCoreTests` (test target).

The core's platform dependencies become protocols, named after their Windows counterparts so the two
ports stay legible side by side: `DictionaryValidating` (`IDictionaryValidator`), `LayoutCatalog`
(`ILayoutCatalog` — enumerate installed layouts, render keys through one, report the current), and a
log sink the executable wires to `rslog`. `Dict`, `LayoutSwitcher` and `DynamicKeyMapping` stay in the
executable as the production conformances.

*Why protocols rather than `#if canImport(AppKit)` shims:* the tests must be deterministic on any
machine, and today's results depend on which layouts and system dictionaries the developer happens to
have installed. Injection is what makes `evaluate` assertable at all.

*Why not extract more:* the retype engine, layout switching and the caret work are inseparable from
AppKit/Carbon and would need a UI-level harness to be worth testing. The value is concentrated in the
decision logic — the part that decides whether to touch the user's text.

### D7 — Ordering: security first, then the safety net, then the rest

1. Password guard (+ its diagnostic and the always-on log channel).
2. Package split and tests.
3. Notifications.
4. Chip.

*Why not tests first, as a safety net for the rest:* the guard is the item with live exposure, it is
almost entirely untestable by unit tests anyway (it is an AX integration), and it touches the
conversion path only by adding an early return. Shipping it should not wait on a refactor. Steps 2–4
then land with the suite in place.

### D8 — New strings are authored in en/uk/ru; the other 13 languages fall back

`L10n.s()` already falls back to English for missing keys, and the app's three subject languages are
the ones its users type in. Authoring 13 more translations for a keycap hint and two notification
bodies is not a good use of the change.

## Risks / Trade-offs

- **AX query in the hot path stalls typing** → 0.05 s messaging timeout, per-element memoization, and
  a verdict computed once per word rather than per consumer (D2). Timeout resolves to
  not-a-password, so a stall can never *also* become a hang.
- **The wording heuristic over-blocks a legitimate field** — e.g. a field named "Password hint" or a
  search box on a page about passwords → accepted by design (D1). The user can still convert it with…
  nothing, actually: the manual trigger is gated too (D3). Mitigation is the diagnostic: the log and
  the `diagpw`-equivalent mode name which signal fired, so a bad match is reportable rather than
  mysterious.
- **The guard silently never fires** — the exact Windows failure, invisible for four releases →
  the per-word verdict line is a spec requirement, not an implementation nicety, and the acceptance
  check for this change is verifying it on the *installed, signed* app rather than a debug build.
- **Package split destabilizes the shipped hot path** → the extraction is mechanical and lands in its
  own commit with no behavior edits; `build_app.sh` and the signed-install loop are exercised before
  anything is built on top of it.
- **Chip on by default annoys users who liked silence** → it is a single switch in Settings, it fades
  after ~1.6 s, and it is click-through. If it proves unwanted the default flips without a code change.
- **Notification authorization denied** → strictly degraded: the offer and the error are logged, the
  conversion path is untouched. The learn-from-undo capability is *reduced* for those users, since the
  modal alert is being removed — accepted, because the alert's cost is paid by every user on every
  offer, and the exceptions list remains reachable in Settings.
- **Trailing docs drift** → the user guide exists in three languages and is compiled into the Help
  window by the build; a missing guide fails the build, so the doc task cannot be silently skipped.

## Migration Plan

- No data migration: all new state is additive (`conversionChip` setting key, defaulting on when
  absent). No existing key changes meaning.
- No permission migration: Accessibility is already granted and already required.
- The package restructure is source-only; the produced app bundle, its identity, and its signing are
  unchanged, so installed TCC grants and the update path are unaffected.
- Rollback: each of the four parts is independently revertable. The guard is an early return, the chip
  and notifications are behind their own call sites, and the package split is a pure refactor commit.

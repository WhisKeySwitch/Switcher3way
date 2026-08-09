# Switcher3way — project handover

macOS menu-bar app that **auto-detects the language of what you type and switches the keyboard
layout** across **three** languages: English (Latin), Ukrainian, Russian. It's a fork of
[rashn/RuSwitcher](https://github.com/rashn/RuSwitcher) (MIT) that generalizes the original
two-layout design to N-way. Pure Swift + AppKit, SwiftPM, universal (arm64 + x86_64), macOS 13+.

> Naming: the **product/app is "Switcher3way"** (`com.switcher3way.app`); the **SwiftPM
> target/module is `Switcher3w`** with sources in `Sources/Switcher3w/` (renamed from upstream's
> `RuSwitcher` in July 2026 — all app-owned identifiers use `switcher3w`/`Switcher3w`; mentions
> of the *upstream project* rashn/RuSwitcher in URLs/attribution are intentionally untouched).
> Code comments are in English (the upstream Russian comments were translated in July 2026);
> write new comments in English.

## Quick start (IDE)

- **Xcode:** `File → Open…` → select `Package.swift` (open the *package*, not a folder). Scheme
  `Switcher3w` builds the executable. Note: running from Xcode won't have TCC permissions under
  Xcode's signature — for real testing, build the bundle with the script below and launch the
  installed `.app`.
- **VS Code / Cursor:** open the `~/RuSwitcher-3way` folder; install the Swift extension for
  LSP. Build/run via the terminal script (Xcode's debugger is optional).
- The Claude Code IDE plugin auto-loads this file for context.

## Build · sign · install (the real loop)

```bash
cd ~/RuSwitcher-3way
bash build_app.sh                       # SwiftPM release (universal) → Switcher3way.app, signed
cp -R Switcher3way.app /Applications/    # install
open /Applications/Switcher3way.app
```

- `version.json` is the **single source of truth** for version/build (stamped into Info.plist by
  the script; the repo Info.plist version is ignored).
- Signing uses a **stable self-signed cert** `Switcher3way Self-Signed` (login keychain; see
  `signing/README.md`). This is what makes macOS permissions survive rebuilds. Falls back to
  ad-hoc if the identity is missing (then permissions reset every rebuild — avoid).
- Drag-install DMG for another Mac: see "Make a drag-install DMG" in `NOTES-3WAY.md`
  (currently `~/Desktop/Switcher3way-<version>.dmg`).

## Permissions (required to function)

The app needs **Accessibility** (read/rewrite text) and **Input Monitoring** (see keystrokes).
Grant once in System Settings → Privacy & Security. With the stable cert these persist across
rebuilds. Verify from the log (see Debugging): `Permissions: accessibility=true inputMonitoring=true`.
If accessibility is false, the app can't convert anything — this was the entire cause of an
earlier "it doesn't work".

## What this fork changed vs upstream

Rationale + detail: `NOTES-3WAY.md`. Summary:

1. **N-way detection** — `NWayDetector.swift` (`NWayResolver.evaluate`). Renders the typed
   keystrokes through *every* installed layout that has a macOS dictionary, validates each
   candidate in its own language, switches to the single unambiguous winner. Words valid in
   **both** uk & ru (e.g. `там`, `добре`) convert to the preferred ambiguity language
   (Auto-fix setting, default uk; "off" = leave alone); `PhraseTracker.swift` re-converts
   them when a later word locks the phrase to the other language (July 2026).
2. **Rename** to Switcher3way (Info.plist identity, `build_app.sh`, all UI strings, menu header).
3. **Updater rebuilt for the fork** — the upstream updater was deleted at fork time (so
   stock 2-way upstream releases couldn't clobber the fork); July 2026 added a new one
   (`UpdateChecker.swift` + `UpdateInstaller.swift`) whose ONLY source is the fork's own
   public releases repo (`WhisKeySwitch/switcher3way-releases`): daily background check
   (General-tab toggle, default on) + "Check for Updates…" menu item; notify → one-click
   verified install (manifest sha256 + same-certificate codesign gate — that's what keeps
   TCC permissions across updates) → relaunch via `AppRelauncher`.
4. **Custom icon** — `icon-design/` (S / Э / Є cycling; `generate_icon_3way.swift`).
5. **UI trims** — About tab buttons removed; Advanced tab "Send log" removed; General tab
   "check for updates" checkbox removed (returned in July 2026 with the fork's own updater,
   see 3); note added explaining auto = all layouts.
6. **Stable signing** — `build_app.sh` signs with the self-signed identity instead of ad-hoc.
7. **UI modernization** (`openspec/changes/modernize-ui`, from the W1–W4 design-review
   wireframes): Settings became toolbar-tab preferences (General / Auto-fix / Advanced / About)
   with grouped forms and switches; the three exception tables merged into one
   filtered/searchable list; the chained permission alerts became a live onboarding checklist
   window; the menu got a status header, quick-toggles group, and Pause-with-durations
   (new `com.switcher3w.pausedUntil` key; "until restart" is session-only by design).
8. **Identifier rename** (July 2026) — all app-owned `ruswitcher` identifiers became
   `switcher3w`: SwiftPM module/target + `Sources/Switcher3w/`, `com.switcher3w.*` defaults
   keys (with one-time migration), `~/Library/Logs/Switcher3w/switcher3w.log`. Upstream
   references (rashn/RuSwitcher URL in README credits, LICENSE, Info.plist attribution)
   intentionally keep the old name.
9. **Dead weight removed** (July 2026 cleanup) — dormant updater pipeline, upstream README
   (rewritten for the fork), Homebrew cask, upstream icon assets/generators, upstream-stats
   script, `nway-3way.patch`. Only LICENSE + attribution reference upstream now.

## Architecture map

### `Sources/Switcher3wCore/` — the testable decision core (August 2026)

Foundation-only library target, extracted so the logic that decides whether to touch the user's
text is assertable without the app, its permissions, or the machine's installed layouts. Platform
services arrive through protocols, named after their Windows counterparts so the two ports stay
legible side by side.

- **`CoreInterfaces.swift`** — `TypedKey`, `Layout`, and the injection points:
  `DictionaryValidating` (Windows `IDictionaryValidator`), `LayoutCatalog` (`ILayoutCatalog`),
  `WordExceptionList`, plus `CoreLog` (the executable wires it to `rslog` at startup).
- **`SoftGates.swift`** — `passes` (length / all-caps / camelCase / mixed-script vetoes) and
  `letterCore` trimming, shared verbatim by the 2-way and N-way paths.
- **`NWayResolver.swift`** — `evaluate` / `manualPlan` / `render`. Instance-based; the executable
  owns one (`NWay.resolver`).
- **`PhraseTracker.swift`** — phrase memory and retro-corrections; takes a renderer closure.

`Tests/Switcher3wCoreTests/` covers it (55 cases, `swift test`): soft gates, evaluate outcomes,
manual plan, phrase tracking, and a **dictionary-quality** test measuring the real NSSpellChecker
against `WordFixture.swift`.

### `Sources/Switcher3w/` — the app

- **`AppDelegate.swift`** — lifecycle, menu-bar item + menu (`rebuildMenu`: status header with
  layout badge/trigger hint/version, quick toggles, Pause submenu; "Check Permissions…" appears
  only when permissions are broken), permission checks, status icon (`⏸`-prefixed while
  paused/disabled). **`handleAutoConvert()`** is the auto-switch orchestrator (word boundary →
  `NWayResolver.resolve` → `TextConverter.convertBuffer` + `LayoutSwitcher.switchTo`). Manual
  ⌥-trigger callbacks (`onAltTap`/`onAltReconvert`) also route through N-way; all three gate on
  `SettingsManager.effectivelyEnabled` (master toggle AND not paused); pause timers live in
  `applyEnabledState()`.
- **`NWayDetector.swift`** — the N-way decision (fork's core).
- **`AutoSwitch.swift`** — `Dict` (NSSpellChecker), `LayoutDetector.decide`, `AutoSwitchPolicy`
  (exception lists, denied apps, secure-input, remote). The soft gates now live in the core.
- **`CoreAdapters.swift`** — the production conformances (`SystemDictionary`,
  `SystemLayoutCatalog`, `SettingsExceptionList`) and `NWay.resolver`, the app's single resolver.
- **`SecureFieldDetector.swift`** — the password-field guard (August 2026). Three signals on the
  focused AX element: subrole `AXSecureTextField`, a text field *labelled* as a password (12
  languages — catches unmasked "show password" boxes and JS-masked web forms), and the original
  `IsSecureEventInputEnabled()`. 0.05 s messaging timeout, memoized per focused element, raises
  the Electron/Chromium tree via `AXManualAccessibility`. Gates auto, the manual trigger, and the
  feedback badge. Every failure logs and answers "not a password". `Switcher3way diagpw` prints
  the per-signal breakdown for whatever has focus.
- **`ConversionNotifier.swift`** — `UNUserNotificationCenter`: the throttled "couldn't rewrite
  here" error and the learn-from-undo offer (a notification with an action button, replacing the
  modal alert). Guarded on `Bundle.main.bundleIdentifier != nil` so `swift run` never traps;
  a denial degrades to logging.
- **`KeyboardMonitor.swift`** — CGEvent tap, keystroke buffer (`currentWordKeys`/`prevWordKeys`),
  word-boundary logic, `rslog`, `TriggerConfig`. Buffer resets on arrows/mouse/app-switch (guards
  against deleting the wrong text).
- **`DynamicKeyMapping.swift`** — `UCKeyTranslate` keycode↔char per layout; `convertKeys`,
  `layoutDataForSource`, `translateKeycode`.
- **`LayoutSwitcher.swift`** — TIS layout control: `switchTo(layoutID:)`, `switchToOpposite`,
  `installedLayouts`, `currentLayoutID`, `languageCode`, `autoDetectID1/2`.
- **`TextConverter.swift`** — retype engine (backspace + Unicode insert, clipboard fallback):
  **`beginCycle`**/**`cycleStep`** (N-way candidate cycle — records the pre-conversion layout so
  undo restores it exactly), `reconvert` (clipboard/selection path only).
- **`SettingsManager.swift`** — UserDefaults (`layout1ID`/`layout2ID` are **dormant** — the old
  manual-trigger pair, no longer read; retained for rollback;
  exception lists; feature flags; pause state: persisted `pausedUntil` + session-only
  `pausedUntilRestart`, computed `isPaused`/`effectivelyEnabled`). Keys are literal
  `com.switcher3w.*` strings; `migrateLegacyDefaults()` (called from main.swift before any
  settings read) copies old `com.ruswitcher.*` values once — old keys stay as rollback insurance.
- **`SettingsWindowController.swift`** — Settings as `NSTabViewController` toolbar tabs
  (System-Settings style): General / Auto-fix / Advanced / About, grouped forms with
  `NSSwitch`es, Auto Layout throughout (no more hand-placed frames).
- **`FormUI.swift`** — `FormBox` (grouped box with hairline row separators) + row/header/
  footnote/badge factories shared by Settings tabs and the onboarding checklist.
- **`ExceptionsPane.swift`** — unified exceptions list (one table + segmented filter with live
  counts + search + add/remove; protected password-manager rows show an "always off" badge).
- **`OnboardingWindowController.swift`** — permission checklist window: 1 s live polling of
  both grants, inline launch-at-login switch; replaced the chained NSAlert wizard.
- **`HelpWindowController.swift`** — in-app help: WKWebView window rendering
  `Resources/help/user-guide.<lang>.html`, language re-resolved on every open (uk/ru, else en);
  external links go to the browser. The HTML is generated by `build_app.sh` from
  `docs/user-guide*.md` via `scripts/md2html.py` — the manuals are the single source of truth,
  a missing guide fails the build.
- **`Localization.swift`** — `L10n` strings, 16 languages; `s()` falls back to English.
- **`UpdateChecker.swift`** — fork updater: GitHub Releases API of the public downloads repo,
  numeric semver compare, 15 s-after-launch + daily schedule (gated on the setting), the
  notify alert (Install / Later / Skip This Version), busy state for the menu item.
- **`UpdateInstaller.swift`** — verified install: DMG download → sha256 vs the `version.json`
  release asset (release-notes fallback) → mount → codesign identity must equal the running
  app's → move-aside + `ditto` swap with rollback → relaunch.
- **`CaretIndicator.swift`** — two surfaces on one non-activating click-through panel: the beta
  layout-flag badge (off by default) and the **conversion chip** (`conversionApplied`, on by
  default — typed form struck through → converted form → the configured trigger as an undo hint).
  Falls back to a window anchor when no caret resolves; suppressed by the password guard.
- Others: `PerAppLayoutManager`, `KeyMapping`/`KeyCodes`
  (static fallback tables), `AppRelauncher` (used by onboarding's restart and the updater).

## Debugging

```bash
defaults write com.switcher3way.app com.switcher3w.debugLog -bool true   # enable file log
# restart app, then:
tail -f ~/Library/Logs/Switcher3w/switcher3w.log

swift test                                            # the detection core's suite (no app needed)
/Applications/Switcher3way.app/Contents/MacOS/Switcher3way diagpw   # password-guard breakdown
```

`diagpw` samples after a 3 s countdown, so you can click into the field you want inspected. It
prints the verdict AND each signal, which is the point: a guard that never fires and a guard that
correctly finds nothing produce identical logs otherwise.

`rslog(...)` is gated behind the debug flag; **`logAlways(...)`** writes regardless, for failures
the user could otherwise never report (AX unavailable, notification registration failing). The
log never records which key was pressed — only that one was buffered.
Logging is gated behind that flag (off by default → no log file otherwise). Startup line reports
permission state. `rslog(...)` is the logger; auto-convert decisions log as `auto: …`.

## Conventions & gotchas

- Module/target name is `RuSwitcher`; product is `Switcher3way`. Keep separate.
- Every rebuild re-signs with the same stable cert → permissions persist. If they suddenly reset,
  the keychain identity is missing — re-import per `signing/README.md`.
- **Never commit** `signing/cert.p12` / private key (git-ignored). Don't ship it in the DMG.
- On another Mac the app is unnotarized → first launch needs right-click → **Open**.
- Both auto-conversion AND the manual trigger are N-way over all installed layouts. The manual
  trigger converts to the best N-way target (and still acts on ambiguous words, since it's an
  explicit request); repeated triggers cycle through the candidate layouts and back to the
  original. There is no user-configurable layout pair (the old Layout 1/2 pickers were removed).

## Current state

- Feature-complete: 3-way auto + manual switching, renamed, custom icon, in-app updates
  from the fork's own releases repo,
  modernized UI (toolbar-tab Settings, onboarding checklist, status-first menu with Pause),
  stable signing, abort-safe retype + phrase-aware ambiguity resolution (July 2026). Builds
  clean; installed at `/Applications/Switcher3way.app` (v1.2.0 — fork versioning restarted from 1.0).
- **Pending user action:** visual pass of the new UI against the W1–W4 wireframes
  (`openspec/changes/modernize-ui/`) — behavior is verified via debug log, pixels are not.

## Known issues / next steps

- **Icon optical balance** — S/Э/Є are fine; could optically size-match if desired.
- **Git:** work happens on feature branches merged into `main` via PRs on
  `WhisKeySwitch/Switcher3way` (origin; the old `yaremenko2205/switcher3w` URL redirects there).
  `signing/cert.p12` is git-ignored — keep it that way. Don't commit `Switcher3way.app`.

## Reference docs

- `docs/user-guide.md` (+ `.uk.md`, `.ru.md`) — end-user manual (EN/UK/RU); keep in sync with
  UI/behavior changes — it documents trigger semantics, auto-fix gates, exceptions, pause.
  Also compiled into the app's Help window on every build (`scripts/md2html.py`).
- `NOTES-3WAY.md` — fork rationale, rebuild/DMG commands, detection policy, icon, updates.
- `signing/README.md` — the stable code-signing identity (setup, re-import, backup).
- `openspec/` — OpenSpec capability specs back-filled from the code (`CAPABILITIES.md` is the
  overview; validate with `openspec validate --specs`). Software updates are a first-class
  capability (`specs/software-updates/`) since July 2026 — the updater targets only the fork's
  own releases repo.

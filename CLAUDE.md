# Switcher3way — project handover

macOS menu-bar app that **auto-detects the language of what you type and switches the keyboard
layout** across **three** languages: English (Latin), Ukrainian, Russian. It's a fork of
[rashn/RuSwitcher](https://github.com/rashn/RuSwitcher) (MIT) that generalizes the original
two-layout design to N-way. Pure Swift + AppKit, SwiftPM, universal (arm64 + x86_64), macOS 13+.

> Naming: the **product/app is "Switcher3way"** (`com.switcher3way.app`); the **SwiftPM
> target/module is `Switcher3w`** with sources in `Sources/Switcher3w/` (renamed from upstream's
> `RuSwitcher` in July 2026 — all app-owned identifiers use `switcher3w`/`Switcher3w`; mentions
> of the *upstream project* rashn/RuSwitcher in URLs/attribution are intentionally untouched).
> Upstream code comments are in Russian; keep that style when editing existing files.

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

1. **N-way detection** — `NWayDetector.swift` (`NWayResolver.resolve`). Renders the typed
   keystrokes through *every* installed layout that has a macOS dictionary, validates each
   candidate in its own language, switches to the single unambiguous winner. Precision-first:
   words valid in **both** uk & ru (e.g. `там`) are left alone.
2. **Rename** to Switcher3way (Info.plist identity, `build_app.sh`, all UI strings, menu header).
3. **Updater removed** — auto-update deleted outright (July 2026 cleanup; originally
   disabled so the stock 2-way upstream couldn't clobber the fork). `AppRelauncher` stays
   (used by onboarding's post-grant restart).
4. **Custom icon** — `icon-design/` (S / Э / Є cycling; `generate_icon_3way.swift`).
5. **UI trims** — About tab buttons removed; Advanced tab "Send log" removed; General tab
   "check for updates" checkbox removed; note added explaining auto = all layouts.
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

## Architecture map (`Sources/Switcher3w/`)

- **`AppDelegate.swift`** — lifecycle, menu-bar item + menu (`rebuildMenu`: status header with
  layout badge/trigger hint/version, quick toggles, Pause submenu; "Check Permissions…" appears
  only when permissions are broken), permission checks, status icon (`⏸`-prefixed while
  paused/disabled). **`handleAutoConvert()`** is the auto-switch orchestrator (word boundary →
  `NWayResolver.resolve` → `TextConverter.convertBuffer` + `LayoutSwitcher.switchTo`). Manual
  ⌥-trigger callbacks (`onAltTap`/`onAltReconvert`) also route through N-way; all three gate on
  `SettingsManager.effectivelyEnabled` (master toggle AND not paused); pause timers live in
  `applyEnabledState()`.
- **`NWayDetector.swift`** — the N-way decision (fork's core).
- **`AutoSwitch.swift`** — `Dict` (NSSpellChecker), `LayoutDetector.decide` + shared
  `passesSoftGates`, `AutoSwitchPolicy` (exception lists, denied apps, secure-input, remote).
- **`KeyboardMonitor.swift`** — CGEvent tap, keystroke buffer (`currentWordKeys`/`prevWordKeys`),
  word-boundary logic, `rslog`, `TriggerConfig`. Buffer resets on arrows/mouse/app-switch (guards
  against deleting the wrong text).
- **`DynamicKeyMapping.swift`** — `UCKeyTranslate` keycode↔char per layout; `convertKeys`,
  `layoutDataForSource`, `translateKeycode`.
- **`LayoutSwitcher.swift`** — TIS layout control: `switchTo(layoutID:)`, `switchToOpposite`,
  `installedLayouts`, `currentLayoutID`, `languageCode`, `autoDetectID1/2`.
- **`TextConverter.swift`** — retype engine (backspace + Unicode insert, clipboard fallback):
  `convert`, **`convertBuffer`** (N-way targeted retype), `reconvert`.
- **`SettingsManager.swift`** — UserDefaults (`layout1ID`/`layout2ID` = manual-trigger pair only;
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
- Others: `CaretIndicator` (flag at cursor), `PerAppLayoutManager`, `KeyMapping`/`KeyCodes`
  (static fallback tables), `AppRelauncher` (used by onboarding's restart).

## Debugging

```bash
defaults write com.switcher3way.app com.switcher3w.debugLog -bool true   # enable file log
# restart app, then:
tail -f ~/Library/Logs/Switcher3w/switcher3w.log
```
Logging is gated behind that flag (off by default → no log file otherwise). Startup line reports
permission state. `rslog(...)` is the logger; auto-convert decisions log as `auto: …`.

## Conventions & gotchas

- Module/target name is `RuSwitcher`; product is `Switcher3way`. Keep separate.
- Every rebuild re-signs with the same stable cert → permissions persist. If they suddenly reset,
  the keychain identity is missing — re-import per `signing/README.md`.
- **Never commit** `signing/cert.p12` / private key (git-ignored). Don't ship it in the DMG.
- On another Mac the app is unnotarized → first launch needs right-click → **Open**.
- Auto-conversion is N-way over all installed layouts; the Layout 1/2 pickers only set the
  manual-trigger pair. There is intentionally no "third layout" field.

## Current state

- Feature-complete: 3-way auto + manual switching, renamed, custom icon, updater off,
  modernized UI (toolbar-tab Settings, onboarding checklist, status-first menu with Pause),
  stable signing. Builds clean; installed at `/Applications/Switcher3way.app` (v1.0.0 — fork versioning restarted from 1.0).
- **Pending user action:** visual pass of the new UI against the W1–W4 wireframes
  (`openspec/changes/modernize-ui/`) — behavior is verified via debug log, pixels are not.

## Known issues / next steps

- **⌥ undo layout** (5-sec window) after an auto-switch retypes the original text correctly but
  may switch to the wrong layout in pure 3-way (built around a pair). Fix: record the pre-switch
  layout ID in `AutoConverter`/conversion state and restore it on undo.
- **Icon optical balance** — S/Э/Є are fine; could optically size-match if desired.
- **Git:** all fork changes are committed on `main` (repo is a shallow clone of upstream; no
  remote push). `signing/cert.p12` is git-ignored — keep it that way. Don't commit `Switcher3way.app`.

## Reference docs

- `docs/user-guide.md` (+ `.uk.md`, `.ru.md`) — end-user manual (EN/UK/RU); keep in sync with
  UI/behavior changes — it documents trigger semantics, auto-fix gates, exceptions, pause.
  Also compiled into the app's Help window on every build (`scripts/md2html.py`).
- `NOTES-3WAY.md` — fork rationale, rebuild/DMG commands, detection policy, icon, updates-off.
- `signing/README.md` — the stable code-signing identity (setup, re-import, backup).
- `openspec/` — OpenSpec capability specs back-filled from the code (`CAPABILITIES.md` is the
  overview; 10 specs under `specs/`; validate with `openspec validate --specs`). Update checking
  is documented there as intentionally disabled — don't spec the dormant updater pipeline.

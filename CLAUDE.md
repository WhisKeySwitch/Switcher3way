# Switcher3way — project handover

macOS menu-bar app that **auto-detects the language of what you type and switches the keyboard
layout** across **three** languages: English (Latin), Ukrainian, Russian. It's a fork of
[rashn/RuSwitcher](https://github.com/rashn/RuSwitcher) (MIT) that generalizes the original
two-layout design to N-way. Pure Swift + AppKit, SwiftPM, universal (arm64 + x86_64), macOS 13+.

> Naming quirk: the **product/app is "Switcher3way"** (`com.switcher3way.app`), but the **SwiftPM
> target/module stays `RuSwitcher`** and sources live in `Sources/RuSwitcher/` — a Swift module
> name can't start with a digit. Don't "fix" this mismatch; it's deliberate. Upstream code
> comments are in Russian; keep that style when editing existing files.

## Quick start (IDE)

- **Xcode:** `File → Open…` → select `Package.swift` (open the *package*, not a folder). Scheme
  `RuSwitcher` builds the executable. Note: running from Xcode won't have TCC permissions under
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

Full diff: `nway-3way.patch`. Rationale + detail: `NOTES-3WAY.md`. Summary:

1. **N-way detection** — `NWayDetector.swift` (`NWayResolver.resolve`). Renders the typed
   keystrokes through *every* installed layout that has a macOS dictionary, validates each
   candidate in its own language, switches to the single unambiguous winner. Precision-first:
   words valid in **both** uk & ru (e.g. `там`) are left alone.
2. **Rename** to Switcher3way (Info.plist identity, `build_app.sh`, all UI strings, menu header).
3. **Updater disabled** — `UpdateChecker.check()` early-returns; update menu/settings items
   removed. (Upstream repo is stock 2-way; auto-update would clobber the fork.)
4. **Custom icon** — `icon-design/` (S / Э / Є cycling; `generate_icon_3way.swift`).
5. **UI trims** — About tab buttons removed; Advanced tab "Send log" removed; General tab
   "check for updates" checkbox removed; note added explaining auto = all layouts.
6. **Stable signing** — `build_app.sh` signs with the self-signed identity instead of ad-hoc.

## Architecture map (`Sources/RuSwitcher/`)

- **`AppDelegate.swift`** — lifecycle, menu-bar item + menu (`rebuildMenu`), permission checks,
  status icon. **`handleAutoConvert()`** is the auto-switch orchestrator (word boundary →
  `NWayResolver.resolve` → `TextConverter.convertBuffer` + `LayoutSwitcher.switchTo`). Manual
  ⌥-trigger callbacks (`onAltTap`/`onAltReconvert`) also route through N-way.
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
  exception lists; feature flags). Keys are literal `com.ruswitcher.*` strings (leave them).
- **`SettingsWindowController.swift`** — Settings tabs: General / Auto-conversion (exceptions) /
  About / Advanced. Manual AppKit layout (hand-placed `y` coordinates — adjust carefully).
- **`Localization.swift`** — `L10n` strings, 16 languages; `s()` falls back to English.
- Others: `CaretIndicator` (flag at cursor), `PerAppLayoutManager`, `KeyMapping`/`KeyCodes`
  (static fallback tables), `UpdateChecker` (disabled), `AppRelauncher`.

## Debugging

```bash
defaults write com.switcher3way.app com.ruswitcher.debugLog -bool true   # enable file log
# restart app, then:
tail -f ~/Library/Logs/RuSwitcher/ruswitcher.log
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

- Feature-complete: 3-way auto + manual switching, renamed, custom icon, updater off, UI trimmed,
  stable signing. Builds clean; installed at `/Applications/Switcher3way.app` (v2.6.0).
- **Pending user action:** grant Accessibility + Input Monitoring once (persists thereafter).

## Known issues / next steps

- **⌥ undo layout** (5-sec window) after an auto-switch retypes the original text correctly but
  may switch to the wrong layout in pure 3-way (built around a pair). Fix: record the pre-switch
  layout ID in `AutoConverter`/conversion state and restore it on undo.
- **Icon optical balance** — S/Э/Є are fine; could optically size-match if desired.
- **Git:** working tree has uncommitted fork changes (10 modified, `NWayDetector.swift` added,
  untracked `NOTES-3WAY.md` / `icon-design/` / `signing/` / `nway-3way.patch`). Repo is a shallow
  clone of upstream. Consider committing to a `switcher3way` branch. Don't commit `Switcher3way.app`.

## Reference docs

- `NOTES-3WAY.md` — fork rationale, rebuild/DMG commands, detection policy, icon, updates-off.
- `signing/README.md` — the stable code-signing identity (setup, re-import, backup).
- `nway-3way.patch` — complete diff vs upstream RuSwitcher.

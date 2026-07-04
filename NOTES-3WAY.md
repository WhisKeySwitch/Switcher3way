# Switcher3way — 3-way (en/uk/ru) fork of RuSwitcher

Ships as **Switcher3way** (`com.switcher3way.app`). The internal SwiftPM target/module stays
`RuSwitcher` (module names can't start with a digit); only the product is renamed. Custom fork of
[rashn/RuSwitcher](https://github.com/rashn/RuSwitcher) (MIT) that generalizes
layout detection from a **two-layout pair** to **N-way across every installed layout that has a
macOS system dictionary** — so English + Ukrainian + Russian all participate in auto-switching.

## What changed vs upstream

Summary (the `nway-3way.patch` full diff was removed in the July 2026 cleanup; use git history):

- **`Sources/RuSwitcher/NWayDetector.swift`** (new) — `NWayResolver.resolve()`. Renders the typed
  keystrokes through each installed layout, checks each candidate against its own language's
  `NSSpellChecker` dictionary, and returns the single unambiguous winner (or nil = keep).
- **`AutoSwitch.swift`** — extracted `LayoutDetector.passesSoftGates()` so the 2-way and N-way
  paths share identical precision vetoes (short words, digits, ALL-CAPS, code identifiers).
- **`DynamicKeyMapping.swift`** — exposed `layoutDataForSource` / `translateKeycode` (were private).
- **`TextConverter.swift`** — added `convertBuffer(original:converted:keyCount:trailingSpaces:)`,
  a retype path whose target string is chosen by the caller (not by the pair).
- **`AppDelegate.swift`** — auto-conversion and the manual ⌥ trigger route through `NWayResolver`
  and switch to the detected layout via `switchTo(layoutID:)`. The remote-desktop (Screen Sharing)
  path is left on the original 2-way logic.

## Detection policy

Precision-first. Switch only when the typed word is invalid in the current language AND valid in
**exactly one** other language. Words valid in **both** Ukrainian and Russian (same-script
ambiguity, e.g. `там`) are **left alone** by design — fix those with a manual ⌥ tap.

## Rebuild

```bash
cd ~/RuSwitcher-3way
bash build_app.sh          # produces Switcher3way.app (universal), signed with the stable identity
cp -R Switcher3way.app /Applications/
```

Signed with a **stable self-signed certificate** (`Switcher3way Self-Signed`, see `signing/`), so
Accessibility / Input Monitoring grants **persist across rebuilds** — grant once, done. It's still
not notarized, so on *another* Mac you use right-click → **Open** the first time. If you ever see
permissions drop after a rebuild, the signing identity is missing from the keychain — re-import it
(`signing/README.md`).

## Make a drag-install DMG

```bash
cd ~/RuSwitcher-3way
STAGE=$(mktemp -d); cp -R Switcher3way.app "$STAGE/"; ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Switcher3way" -srcfolder "$STAGE" -ov -format UDZO ~/Desktop/Switcher3way.dmg
```

## Icon

Custom "Triadic Rotation" icon (A / Я / Ї cycling on a gold orbit, azure→violet tile). Source:
`icon-design/generate_icon_3way.swift` (headless AppKit, SF Rounded) + `icon-design/PHILOSOPHY.md`.
Regenerate: `swift icon-design/generate_icon_3way.swift icon-design` → then
`iconutil -c icns icon-design/Switcher3way.iconset -o Switcher3way.icns`. `build_app.sh` copies
`Switcher3way.icns` into the bundle. After reinstalling, refresh the icon cache with
`touch /Applications/Switcher3way.app && killall Dock Finder`.

## Updates disabled

The updater was deleted outright in the July 2026 cleanup (originally `UpdateChecker.check(silent:)`
was short-circuited — returned before any network call) so the fork can
never auto-update itself back to upstream stock RuSwitcher. Manual "Check for updates…" just shows
"up to date". To re-enable, remove the early-return block at the top of `check(silent:)`.

## Known limitation

The 5-second ⌥ *undo* after an auto-switch retypes the original text correctly, but its
layout-toggle-back can be wrong in pure 3-way (it was built around a pair). Proper fix: record the
pre-switch layout ID in the conversion state and restore it on undo.

## Full notarized distribution (optional)

`create_dmg.sh` already supports Developer-ID signing + `notarytool` + stapling. With an Apple
Developer account, set the signing identity / keychain profile it expects and it produces a DMG
that installs with zero Gatekeeper friction on any Mac.

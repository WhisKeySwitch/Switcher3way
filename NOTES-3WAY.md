# Switcher3way — 3-way (en/uk/ru) fork of RuSwitcher

Ships as **Switcher3way** (`com.switcher3way.app`). The internal SwiftPM target/module stays
`RuSwitcher` (module names can't start with a digit); only the product is renamed. Custom fork of
[rashn/RuSwitcher](https://github.com/rashn/RuSwitcher) (MIT) that generalizes
layout detection from a **two-layout pair** to **N-way across every installed layout that has a
macOS system dictionary** — so English + Ukrainian + Russian all participate in auto-switching.

> **Windows port:** there's also a C#/.NET Windows build under [`windows/`](windows/). Its release
> process (self-contained MSI, `windows-v<ver>` pre-release tag, download-page update) is documented
> in [`windows/RELEASING.md`](windows/RELEASING.md) — this file covers macOS only.

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
ambiguity, e.g. `там`, `добре`) convert to the **preferred ambiguity language** (Settings →
Auto-fix; default Ukrainian, "Do not convert" restores the old keep). A `PhraseTracker` remembers
the phrase: when a later word is valid in exactly one language, earlier ambiguity-defaulted words
are re-converted to it in one segment replacement (single ⌥ undo; contradictory phrases untouched).

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

## Updates

History: the upstream updater was deleted at fork time so the fork could never auto-update
itself back to stock rashn/RuSwitcher. In July 2026 a new updater was built whose ONLY source
is the fork's own releases — so that risk no longer exists. Originally those lived in a
separate public downloads repo (`WhisKeySwitch/switcher3way-releases`); in August 2026 the
releases were consolidated onto the main repo (`WhisKeySwitch/Switcher3way`), which the updater
now targets. **One-time bridge:** every app installed at ≤1.3.0 still polls the old repo, so the
first release after the consolidation must be published to BOTH repos (same DMG, same
`version.json`, same notes); once it's out, archive the old repo — archived repos keep serving
downloads and the API read-only, so stragglers still reach the bridge. Every later release goes
to the main repo only.

How it works (`UpdateChecker.swift` + `UpdateInstaller.swift`):

- **Check**: GitHub Releases API (`releases/latest`), numeric semver compare against the
  running bundle version. Automatic ~15 s after launch and daily (General-tab toggle,
  default on), plus a "Check for Updates…" menu item. Background failures are silent
  (rslog only); manual checks report every outcome.
- **Offer**: one alert — Install and Relaunch / Later / Skip This Version (skip is
  per-version, cleared by a newer release or a manual check).
- **Verify**: DMG sha256 must match the `version.json` release asset (release-notes checksum
  as fallback for pre-manifest releases), AND the new bundle's codesign leaf certificate must
  equal the running app's (the stable self-signed cert). The identity gate is what keeps
  Accessibility/Input Monitoring grants valid across updates.
- **Install**: mount read-only → move the current bundle aside → `ditto` the new one in →
  rollback on failure → strip quarantine → relaunch via `AppRelauncher`.

**Release-flow requirement**: every release on the main repo MUST attach
`version.json` as an asset next to the DMG (`gh release create … Switcher3way-X.Y.Z.dmg
version.json`) — it's the updater's checksum source of truth. Keep the sha256 in the release
notes too (human verification + fallback).

(The trigger's ambiguous-word layout fix — `*-fix-collapsed-layout-candidates` — shipped in
1.3.0 and its release notes called it out, as intended.)

## Known limitation

The 5-second ⌥ *undo* after an auto-switch retypes the original text correctly, but its
layout-toggle-back can be wrong in pure 3-way (it was built around a pair). Proper fix: record the
pre-switch layout ID in the conversion state and restore it on undo.

## Notarized distribution

`create_dmg.sh` signs with Developer ID, notarizes the **app bundle** and staples it, then signs,
notarizes and staples the **DMG** — both, deliberately: a bundle dragged out of an unstapled image
falls back to an online Gatekeeper check and fails offline, and an unsigned container makes some
Macs distrust the app extracted from it.

Setup is one-time and lives in `signing/README.md`: a Developer ID Application certificate, a
`notarytool` keychain profile, and `signing/developer-id.conf` filled in. Nothing is hardcoded —
the script used to carry the *upstream* project's Developer ID, which would have failed
notarization under this account.

```bash
bash create_dmg.sh                    # signed + notarized + stapled, ready to ship
SKIP_NOTARIZE=1 bash create_dmg.sh    # local test image; will NOT pass Gatekeeper elsewhere
```

**Where a notarized release may be published.** Until the last self-signed installs have
crossed over, a Developer ID release goes to `switcher3way-releases` ONLY, never to the main
repo. Copies still at 1.5.2 or earlier poll the main repo and carry no `RSReleaseTeamID`, so
they fall back to comparing certificate bytes — and a Developer ID signature can never match a
self-signed one. If the main repo's `latest` becomes a notarized build, every one of those
installs fails its update silently and forever, with no way to reach it.

So the main repo's `latest` stays pinned at the bridge (1.6.1). A straggler updates to the
bridge, and the bridge points it at `switcher3way-releases`, where the real latest lives. Only
once those installs are gone does publishing to both stop mattering — and by then the main repo
is private anyway.

**Migrating from the self-signed identity.** The switch changes the app's designated requirement,
which drops Accessibility and Input Monitoring. That path is already handled:
`AppDelegate.runPermissionWizard` notices "granted before, gone now", runs `tccutil reset` to clear
the stale entries (which would otherwise show as ticked but do nothing), and opens the onboarding
checklist with a reset notice. Users re-grant twice, once.

The updater needs no such rescue as long as `signing/developer-id.conf` is filled in **before** the
last self-signed release is cut — see "Why the Team ID is stamped into the bundle" in
`signing/README.md`. If a self-signed build ships without `RSReleaseTeamID`, it can never
auto-update to a Developer ID build and those installs must re-download by hand.

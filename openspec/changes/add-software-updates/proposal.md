## Why

Users who installed Switcher3way from the DMG have no way to learn about or obtain new versions — they'd have to re-visit the releases page by hand. The fork deleted the upstream updater deliberately (so stock rashn/RuSwitcher releases could never clobber the fork), but that rationale is obsolete: the project now publishes its own releases to the public `WhisKeySwitch/switcher3way-releases` repo, with DMG assets, SHA-256 checksums, and a stable signing identity that makes in-place updates preserve macOS permissions. The infrastructure for safe self-updating exists; the feature does not.

## What Changes

- Add an **update checker**: query the public releases repo (GitHub Releases API) for the latest version, compare against the running `CFBundleShortVersionString`, and notify the user when a newer version exists. Checks run at launch and daily (configurable), plus a manual "Check for Updates…" menu item.
- Add **one-click install**: from the update alert (version + release notes; Install / Later / Skip this version), download the DMG, verify its SHA-256 against the published manifest and the app's code-signing identity against the running app, swap the bundle in `/Applications`, and relaunch via the existing `AppRelauncher`.
- Add a **Settings toggle** (General tab): "Check for updates automatically", on by default. New persisted keys under `com.switcher3w.*` (auto-check flag, skipped version, last-check timestamp).
- Add localized strings for the menu item, alert, and settings row (16 languages, English fallback).
- **Release process change**: each release additionally attaches `version.json` as an asset (the update manifest carrying version + DMG sha256).
- **Documentation reversal**: CLAUDE.md, `openspec/CAPABILITIES.md`, and NOTES-3WAY.md currently document update checking as intentionally removed/out of scope — update them to describe the new updater; update the user guides (EN/UK/RU).

## Capabilities

### New Capabilities
- `software-updates`: checking for, notifying about, verifying, and installing new versions from the project's own public releases repository — including the automatic-check schedule and toggle, the skip-version choice, download integrity verification (SHA-256 + code-signing identity), in-place install, and relaunch.

### Modified Capabilities
- `distribution-and-releases`: releases gain an update-manifest requirement — each published release SHALL attach `version.json` (version + DMG sha256) as an asset so the in-app updater can discover and verify it; the public downloads repo is the updater's source of truth.
- `menu-bar-ui-and-status-icon`: the status menu gains a "Check for Updates…" item (new requirement; existing menu requirements unchanged).

## Impact

- **New code**: `UpdateChecker.swift` (API query, semver compare, schedule), `UpdateInstaller.swift` (download, verify, swap, relaunch) in `Sources/Switcher3w/`.
- **Touched code**: `AppDelegate.swift` (menu item, daily timer, alert flow), `SettingsManager.swift` (new keys), `SettingsWindowController.swift` (General-tab toggle), `Localization.swift` (new strings).
- **Network**: the app gains its first runtime network access (HTTPS to `api.github.com` / `github.com` release assets only, only for update checks/downloads). The Windows-port spec's "no runtime network dependency" statement applies to detection/conversion and is unaffected, but the privacy posture change must be documented in the user guide.
- **Release flow**: DMG releases must additionally upload the `version.json` manifest asset.
- **Docs**: CLAUDE.md, CAPABILITIES.md, NOTES-3WAY.md ("Updates disabled" section), user guides EN/UK/RU, README (optional mention).
- **Risk**: self-replacement of a running unnotarized app (quarantine, Gatekeeper) — addressed in design; the stable-cert identity check prevents installing a foreign bundle.

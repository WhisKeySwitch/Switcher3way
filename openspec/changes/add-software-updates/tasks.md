## 1. Update checker core

- [x] 1.1 Add `UpdateChecker.swift`: fetch `releases/latest` from the public downloads repo via URLSession, parse tag/notes/assets, numeric semver compare against `CFBundleShortVersionString`
- [x] 1.2 Add persisted settings keys to `SettingsManager`: `checkForUpdates` (default true), `skippedVersion`, `lastUpdateCheck`
- [x] 1.3 Implement check scheduling: ~15s-after-launch check + 24h repeating timer, gated on the setting; silent logging (`rslog`) for background failures

## 2. Installer

- [x] 2.1 Add `UpdateInstaller.swift`: download DMG to temp, strip quarantine xattr, compute SHA-256
- [x] 2.2 Resolve expected checksum: `version.json` release asset first, release-body `SHA-256:` fallback; abort install when neither is available or on mismatch
- [x] 2.3 Mount DMG (`hdiutil attach -nobrowse -readonly`), locate the bundle, verify code signature validity and certificate equality with the running app (Security framework)
- [x] 2.4 Implement move-aside → `ditto` copy → detach → `AppRelauncher.relaunch()`, with rollback of the old bundle on any post-move failure and cleanup of temp artifacts

## 3. UI wiring

- [x] 3.1 Add "Check for Updates…" menu item (utility group, before Settings) with in-progress disabled state
- [x] 3.2 Implement the update alert: version + truncated release notes, Install and Relaunch / Later / Skip This Version; wire skip persistence and manual-check skip override
- [x] 3.3 Interactive results for manual checks: up-to-date alert and error alert

## 4. Settings and localization

- [x] 4.1 Add the "Check for updates automatically" switch to the Settings General tab, bound to the new key
- [x] 4.2 Add `L10n` strings (menu item, alert title/body/buttons, settings row, up-to-date/error messages) for all 16 languages with English fallback

## 5. Documentation

- [x] 5.1 Update CLAUDE.md (fork-changes list + architecture map + current state) and NOTES-3WAY.md ("Updates disabled" → new updater description)
- [x] 5.2 Update `openspec/CAPABILITIES.md`: remove update checking from "Explicitly out of scope", add the new capability summary
- [x] 5.3 Update user guides (EN/UK/RU): updates section — how checks work, the toggle, privacy note (GitHub-only network access)
- [x] 5.4 Document the release-flow addition (attach `version.json` asset) in NOTES-3WAY.md

## 6. Release-flow integration

- [x] 6.1 Attach `version.json` as an asset when cutting releases in the public downloads repo (and code repo release, for symmetry)

## 7. Verification

- [ ] 7.1 Build signed app; verify menu item, settings toggle, and localized strings render
- [ ] 7.2 Test manual check against the live public repo (current = latest → "up to date"); test with a locally lowered bundle version → update prompt appears with 1.0.2 notes
- [x] 7.3 End-to-end install test: run the lowered-version build, click Install and Relaunch, confirm the released 1.0.2 replaces it, relaunches, and permissions survive
- [ ] 7.4 Verify skip-version persistence, Later behavior, background-failure silence (network off), and `openspec validate --specs`

# Tasks: publish-dmg-release

## 1. Build the DMG

- [x] 1.1 Confirm `version.json` is `1.0.0` / build `34` and the working tree is clean (no uncommitted source changes that should be in the release)
- [x] 1.2 Run `SKIP_NOTARIZE=1 bash create_dmg.sh`; confirm it rebuilds from source and its bundle-vs-`version.json` version check passes, producing `Switcher3way-1.0.0.dmg`
- [x] 1.3 Sanity-check the artifact: mount the DMG and verify the bundled app's `CFBundleShortVersionString` is `1.0.0`, then detach

## 2. Rewrite the README Install section

- [x] 2.1 Replace the Install section so the **primary** path is: download `Switcher3way-1.0.0.dmg` from the latest release, drag `Switcher3way.app` to `/Applications`, right-click → **Open** on first launch (unnotarized)
- [x] 2.2 Add a secondary **"Build it yourself"** subsection with corrected steps: `git clone https://github.com/yaremenko2205/switcher3w.git`, `cd switcher3w`, `bash build_app.sh` (note Swift/Xcode toolchain prerequisite), `cp -R Switcher3way.app /Applications/`
- [x] 2.3 Correct the signing note: permissions survive rebuilds only after setting up the stable self-signed cert per `signing/README.md`; otherwise `build_app.sh` signs ad-hoc and permissions reset each rebuild
- [x] 2.4 Keep the Accessibility / Input Monitoring onboarding note; ensure a release-download link (releases page) is referenced
- [x] 2.5 Commit the README change (on branch `docs-dmg-release`, PR #2)

## 3. Publish the release

- [x] 3.1 Create git tag `v1.0.0` at the release commit and push it to `origin`
- [x] 3.2 `gh release create v1.0.0` on `yaremenko2205/switcher3w` with `Switcher3way-1.0.0.dmg` attached and release notes describing the app + the right-click → **Open** first-launch caveat
- [x] 3.3 Verify the release page shows the DMG asset and the tag resolves to the correct commit

## 4. Cleanup & verification

- [x] 4.1 Remove the stale `~/Desktop/Switcher3way-2.6.0.dmg` so it can't be mistaken for the current download
- [x] 4.2 Follow the README primary path end-to-end (download the published DMG to a scratch location, open it, confirm drag-install works and the app version is `1.0.0`)
- [x] 4.3 Confirm the build-from-source commands are copy-paste correct against a fresh clone path (dry-check the directory name and clone URL resolve)

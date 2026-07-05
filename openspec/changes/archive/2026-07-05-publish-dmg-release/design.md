## Context

Distribution has never been wired up for the fork. The README's Install section only documents build-from-source, and that block is itself broken (`cd RuSwitcher-3way` matches no clone; no `git clone`; a stable-cert claim that's false for fresh cloners). Meanwhile `create_dmg.sh` already exists and produces a styled drag-install DMG. No GitHub release has ever been published (`gh release list` is empty), and the only DMG on disk is a stale `Switcher3way-2.6.0.dmg` on the maintainer's Desktop — current `version.json` is `1.0.0` / build `34`.

`create_dmg.sh` (read for this change) already does the right safety things: it rebuilds from source via `build_app.sh`, then hard-fails if the built bundle's `CFBundleShortVersionString`/`CFBundleVersion` don't match `version.json` — so a version-mismatched DMG (the 2.6.0 problem) cannot be shipped. Its one wrinkle: it defaults to Apple notarization (`NOTARIZE_PROFILE=notarytool-studio`) unless `SKIP_NOTARIZE=1` is set. This fork has no Apple Developer account, so notarization must be skipped.

## Goals / Non-Goals

**Goals:**
- Give non-developers a one-download install: a fresh, correct `Switcher3way-1.0.0.dmg`.
- Publish it as a GitHub release `v1.0.0` on `yaremenko2205/switcher3w`.
- Make the README Install section correct and DMG-first, with an accurate build-from-source fallback.

**Non-Goals:**
- Apple notarization / Developer-ID signing (no account; app stays unnotarized → right-click → Open on first launch).
- CI/automated release pipeline — this is a manual, one-off release; automation can come later.
- Any change to app runtime behavior or the signing model for local dev.

## Decisions

- **Reuse `create_dmg.sh` with `SKIP_NOTARIZE=1`** rather than hand-rolling `hdiutil`. It already rebuilds from source and enforces the bundle-vs-`version.json` version check, which is exactly the guard that prevents another 2.6.0-style stale artifact. Alternative (manual `hdiutil create` per NOTES) rejected: it skips the version guard and the styled layout.
- **Tag `v1.0.0` and publish via `gh release create`**, attaching the DMG. The tag/release version is derived from `version.json`, keeping a single source of truth. Release notes state the unnotarized first-launch caveat.
- **README structure: DMG-first, build-from-source second.** Primary path = download the release DMG, drag to Applications, right-click → Open once. Secondary "Build it yourself" subsection = corrected `git clone https://github.com/yaremenko2205/switcher3w.git` → `cd switcher3w` → `bash build_app.sh` (toolchain prereq noted) → copy to Applications, with the signing note corrected to reflect that stable-cert permission persistence requires `signing/README.md` setup.
- **Discard the stale Desktop DMG.** `~/Desktop/Switcher3way-2.6.0.dmg` is removed so it can't be mistaken for the current download.

## Risks / Trade-offs

- **Unnotarized download triggers Gatekeeper** → Mitigation: release notes and README both state the right-click → **Open** first-launch step; this is inherent to having no Developer account and is out of scope to fix here.
- **Publishing is public and effectively permanent** (a release/tag can be deleted but may be indexed) → Mitigation: maintainer go-ahead already given; the version check in `create_dmg.sh` ensures the artifact is internally consistent before it goes out.
- **`create_dmg.sh` rebuilds the app** so the shipped DMG may differ from the currently-installed local bundle if sources changed → Mitigation: acceptable and desirable (the DMG is built from committed source); verify the resulting bundle version is `1.0.0` before publishing.
- **Wrong `NOTARIZE_PROFILE` default** could make the script hang on `notarytool submit` → Mitigation: always invoke with `SKIP_NOTARIZE=1` for this release.

## Migration Plan

1. Ensure `version.json` is `1.0.0`/`34` and the working tree is clean/committed.
2. `SKIP_NOTARIZE=1 bash create_dmg.sh` → produces `Switcher3way-1.0.0.dmg`; confirm the script's built-in version check passes.
3. Rewrite README Install section; commit.
4. `git tag v1.0.0` and `gh release create v1.0.0` with the DMG attached and notes.
5. Remove the stale `~/Desktop/Switcher3way-2.6.0.dmg`.

Rollback: delete the GitHub release and tag (`gh release delete v1.0.0 --cleanup-tag`) and revert the README commit. No app-runtime state is affected.

## Open Questions

- None blocking. (If a Developer account is added later, revisit notarization so the right-click → Open step can be dropped — tracked as future work, not this change.)

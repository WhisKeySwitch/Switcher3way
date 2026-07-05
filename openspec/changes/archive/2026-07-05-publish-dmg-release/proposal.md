## Why

The README's Install section is the first thing a prospective user reads, and it is currently broken and misleading: it tells people to `cd RuSwitcher-3way` (a directory no clone produces — the repo is `switcher3w`), omits the `git clone` step entirely, and claims permissions "survive rebuilds" via the stable cert when a fresh cloner has no such cert and falls back to ad-hoc signing. Worse, it presents build-from-source as the *only* install path when the project can already produce a drag-install DMG (`create_dmg.sh`). No release is published anywhere, so today there is genuinely nothing to download — the only DMG in existence is a stale `Switcher3way-2.6.0.dmg` on the maintainer's Desktop (current version is 1.0.0). A non-developer cannot install the app.

## What Changes

- Build a fresh, correct **`Switcher3way-1.0.0.dmg`** from the current bundle (v1.0.0 / build 34) using `create_dmg.sh`.
- Publish it as a **GitHub release tagged `v1.0.0`** on `yaremenko2205/switcher3w`, with release notes describing the app and the unnotarized-first-launch caveat.
- Rewrite the README **Install section** to lead with **"Download the DMG → drag to Applications"** as the primary path, stating the right-click → Open first-launch requirement (app is unnotarized).
- Demote build-from-source to a secondary **"Build it yourself"** subsection and fix its errors: add the missing `git clone`, use the correct `switcher3w` directory name, note the Swift/Xcode toolchain prerequisite, and correct the stable-cert claim (permissions persist only after setting up the self-signed cert per `signing/README.md`; otherwise ad-hoc resets them each rebuild).

## Capabilities

### New Capabilities
- `distribution-and-releases`: How the app is packaged and delivered to end users — the drag-install DMG artifact, the published GitHub release keyed to `version.json`, the unnotarized first-launch requirement, and the documented install paths (download-DMG primary, build-from-source secondary).

### Modified Capabilities
<!-- No existing capability spec's requirements change; README/docs and release tooling are not spec'd behavior of the app runtime. -->

## Impact

- **Docs:** `README.md` Install and Documentation sections rewritten.
- **Release artifacts:** new `Switcher3way-1.0.0.dmg`; new GitHub release `v1.0.0` and git tag `v1.0.0` on `origin`.
- **Tooling:** exercises existing `create_dmg.sh` (no code change expected); relies on `version.json` as the single source of version truth.
- **No app source/runtime behavior changes.** The stale `~/Desktop/Switcher3way-2.6.0.dmg` should be disregarded/removed to avoid confusion.
- **Outward-facing:** publishing a public release is irreversible-ish (a release can be deleted but may be indexed); requires maintainer go-ahead, already given.

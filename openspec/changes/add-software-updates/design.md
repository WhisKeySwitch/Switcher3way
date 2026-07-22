## Context

The app is distributed as an unnotarized, self-signed (stable cert `Switcher3way Self-Signed`) drag-install DMG from the public `WhisKeySwitch/switcher3way-releases` repo. `version.json` is the version source of truth and already records the DMG's sha256. `AppRelauncher.relaunch()` exists (used by onboarding). The upstream updater was deleted; this change builds a new one aimed at the fork's own releases. UX decisions already made with the user: **notify + one-click install** (not silent), **daily auto-check on by default**.

## Goals / Non-Goals

**Goals:**
- Discover new versions from the project's own public releases repo; never from upstream rashn/RuSwitcher.
- One-click, verified, in-place update that preserves TCC permissions (same signing identity) and relaunches.
- Respect user choice: auto-check toggle, "Later", and per-version "Skip".
- Fail quietly in background checks (no network nagging); fail loudly only on user-initiated checks/installs.

**Non-Goals:**
- Silent/fully-automatic installation (explicitly rejected in favor of notify + one-click).
- Sparkle or any third-party update framework (pure Swift + URLSession keeps the zero-dependency stance).
- Delta updates, release channels/betas, downgrade support.
- Notarization (separate, blocked on Apple Developer account).

## Decisions

### D1 — Update source: GitHub Releases API of the public downloads repo
`GET https://api.github.com/repos/WhisKeySwitch/switcher3way-releases/releases/latest` (unauthenticated; 60 req/h/IP is ample for 1–2 checks/day). Fields used: `tag_name` (vX.Y.Z), `body` (release notes for the alert), `assets[]` (DMG + manifest download URLs).
**Alternatives:** scraping `releases/latest` HTML (fragile); committing a manifest file to the repo and fetching raw (second source of truth to keep in sync — rejected; the release *is* the truth).
**Why this repo:** the code repo is private (API 404s without auth); the public downloads repo is exactly the artifact channel users install from.

### D2 — Integrity: manifest sha256 + code-signing identity match
Two independent gates before installing:
1. **SHA-256**: each release attaches `version.json` as an asset; the updater downloads it, reads `sha256`, and verifies the downloaded DMG. For releases published before this change (v1.0.0–v1.0.2) the manifest asset is absent → fall back to parsing `SHA-256: \`hex\`` from the release body; if neither exists, treat as verification failure.
2. **Signing identity**: after mounting the DMG, verify the new bundle's code signature is valid and its signing certificate equals the running app's (via `SecStaticCodeCheckValidity` + certificate comparison). This blocks a tampered or foreign bundle even if the checksum channel were compromised, and guarantees the TCC-permission continuity that the stable cert provides.

### D3 — Install mechanics: mount → verify → move-aside → copy → relaunch
1. Download DMG to a temp dir via `URLSession` (the app has no `LSFileQuarantineEnabled`, so no quarantine xattr is applied; strip it defensively anyway with `removexattr`).
2. `hdiutil attach -nobrowse -readonly`; locate `Switcher3way.app` on the volume.
3. Run D2 verification on the mounted bundle.
4. Move the current `/Applications/Switcher3way.app` to a temp "old" path (moving a running app is safe — its pages stay mapped), copy the new bundle in with `ditto` (preserves signatures/xattrs), `hdiutil detach`.
5. `AppRelauncher.relaunch()` (already sleeps 1s then `open`s the bundle path); delete the old copy on next launch (or best-effort immediately).
On any failure after the move-aside, move the old bundle back (rollback) and surface the error.

### D4 — Scheduling: launch check + 24h repeating timer, all on the main actor
Check ~15s after launch (don't compete with startup/permission flows), then a 24h `Timer`. Persisted keys: `com.switcher3w.checkForUpdates` (Bool, **default true**), `com.switcher3w.skippedVersion` (String), `com.switcher3w.lastUpdateCheck` (Date, informational). Manual "Check for Updates…" ignores `skippedVersion` and reports "you're up to date" / errors interactively.

### D5 — Version comparison: numeric segment compare of the semver triple
Strip `v` prefix, split on `.`, compare numerically segment-wise (missing segments = 0). No pre-release/build-metadata support (the project doesn't use them; `dev` tag builds never auto-update because comparison uses the bundle's `CFBundleShortVersionString`).

### D6 — UX: one NSAlert, three choices
Alert (app active, on demand or when a background check finds something): title "Switcher3way X.Y.Z is available", informative text = truncated release notes, buttons **Install and Relaunch** / **Later** / **Skip This Version**. Progress during download/install via the alert being replaced by a small progress alert or menu-item state ("Downloading update…" disabled item) — keep it minimal, no new window controller. Localized via `L10n` (16 languages, English fallback).

### D7 — Menu placement
"Check for Updates…" sits with Settings/Help in the utility group (before Settings), always visible. While a check/install is running the item shows a disabled in-progress title.

## Risks / Trade-offs

- **[Gatekeeper on the replaced bundle]** → the updater's own download path adds no quarantine attribute; identity check ensures it's our cert; the app was already launched once on this Mac so there is no first-launch prompt for an unquarantined bundle. Belt-and-braces xattr strip on the DMG and the copied bundle.
- **[GitHub API rate limit / offline]** → background check failures are logged (`rslog`) and silently rescheduled; only manual checks alert the user.
- **[Older releases lack the manifest asset]** → body-parse fallback (D2); new releases always attach the manifest (spec delta on distribution-and-releases).
- **[Replacing the running app fails mid-way (permissions, disk)]** → move-aside + rollback (D3); the running process is unaffected until relaunch, so a failed install never leaves a broken install.
- **[User declines forever]** → "Later" re-prompts next check; "Skip This Version" persists per-version and is reset by the next newer release or a manual check.
- **[Privacy posture change: first runtime network access]** → document in user guide + release notes; checks are off with a single toggle; no telemetry, only GET requests to GitHub.

## Migration Plan

Ship as a normal minor release (1.1.0 — new user-facing feature, not a patch): implement → PR → merge → bump `version.json` → release with the new manifest asset attached. The first updater-equipped version obviously can't be delivered by the updater; from the *next* release onward the in-app flow takes over. Rollback = revert the PR; no data migration (new defaults keys are additive).

## Open Questions

- None blocking. (Deferred: surfacing download progress more richly; release channels; Windows-side updater — the Windows MVP will need its own mechanism later.)

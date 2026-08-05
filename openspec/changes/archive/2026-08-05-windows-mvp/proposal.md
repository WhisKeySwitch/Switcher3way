> **Reconciled 5 August 2026.** Everything below is the plan as written before the app shipped. Two of its
> premises no longer hold, and `tasks.md` marks the affected items `[—]`:
>
> * **Code signing as phase-1 infrastructure** — this drove the SignPath Foundation plan (M4) and the CI
>   pipeline. Distribution went to the **Microsoft Store** instead, which signs submitted packages itself,
>   so no certificate of ours is needed and SignPath was never applied for. The direct-download MSI is
>   unsigned by choice, with a SmartScreen click-through.
> * **Shell framework undecided (WPF vs WinForms)** — the app shipped on **WinUI 3**. The WinForms tray and
>   settings window this change built were replaced by the redesign and their files have been deleted.
>
> The detection core, dictionaries, live loop and exception model described here are what shipped and are
> still in use. See the archived `2026-08-05-windows-winui3-redesign` for the decisions that superseded
> the rest.

## Why

The `windows-win32-spike` (archived 2026-07-21) proved the Win32 mechanics on real Windows and
returned a **GO** verdict: per-layout `ToUnicodeEx` rendering, foreground layout switching,
`SendInput` rewrite, and the N-way manual cycle all work for EN/UK/RU. Now build the real app that
satisfies the `windows-platform-support` contract.

The spike also surfaced the one hard gate: an **unsigned** executable is blocked outright on
EDR-managed devices (Microsoft Defender for Endpoint returns "Access is denied" before any code
runs). So this change treats **code signing as phase-1 infrastructure, not a release afterthought** —
using the free **SignPath Foundation** OSS plan (the project is MIT + public repo, so it qualifies).

## What Changes

- Add a **production** C#/.NET Windows app (separate from the throwaway `windows-spike/`, which is
  cannibalized for proven patterns then removed) implementing `windows-platform-support`:
  - **Portable detection core** — port the platform-independent logic from the macOS app
    (`NWayResolver.resolve`/`manualPlan`, `LayoutDetector.passesSoftGates` + letter-core trimming,
    `AutoSwitchPolicy` exception/pause/per-app rules) to C#, unit-tested against the macOS behavior.
  - **Offline validation** — bundle **Hunspell** + en/uk/ru dictionaries behind the letter-core
    validator interface the detection core expects.
  - **Live auto path** — `WH_KEYBOARD_LL` hook → word boundary → render all layouts → validate →
    switch + rewrite, reusing the spike's dead-key-safe renderer, injected-input guard, and
    per-char `SendInput` rewrite.
  - **Manual trigger** — convert-on-demand with the N-way candidate cycle (…→ru→uk→original).
  - **Tray UI + settings + exceptions + per-app memory + localization + diagnostics** — parity
    with the macOS feature set the spec calls for.
  - **Signed distribution from day one** — SignPath-signed, timestamped **executable and
    installer** (MSIX or WiX), wired into GitHub Actions so every build is signed.
- **BREAKING (build/distribution):** the production app produces a real apphost `.exe`
  (`UseAppHost=true`) — unlike the spike, which set `UseAppHost=false` to dodge the EDR block. That
  exe MUST be signed to launch on managed devices; signing is therefore a build prerequisite.
- No changes to the macOS app, its build, signing, or release flow. The Windows app is a parallel
  codebase; the shared detection algorithm is re-ported (per the archived plan's D1 default).

## Capabilities

### New Capabilities
<!-- None. This change implements the existing windows-platform-support capability. -->

### Modified Capabilities
- `windows-platform-support`: sharpen two requirements with what the spike proved —
  (1) *Observe keystrokes and buffer words globally* now requires buffering OEM punctuation/digit
  keys as part of the token (on ЙЦУКЕН the `,` key is `б`, `.` is `ю`, …) and ignoring the app's own
  synthesized keystrokes; (2) *Distribute as a signed, offline application* now requires both the
  executable and the installer to be signed **and timestamped**, and to launch on EDR-managed
  devices (the unsigned-exe block the spike hit).

## Impact

- **New production code**: a Windows C#/.NET solution (tray shell + portable core + Hunspell),
  replacing the throwaway `windows-spike/` (removed once its patterns graduate).
- **New dependencies**: Hunspell + en/uk/ru dictionaries; SignPath signing; an MSIX or WiX
  installer; GitHub Actions signing workflow.
- **Signing/accounts**: apply to the SignPath Foundation OSS program; store the SignPath API token
  as a CI secret. (Azure Trusted Signing is the fallback if SignPath OSS is unavailable, but it is
  US/Canada-only for individuals — see design.)
- **No impact** on the shipping macOS app, its build, signing, or release flow.
- **Docs**: update `CLAUDE.md`/`NOTES-3WAY.md` with the Windows build + signing loop once it lands.

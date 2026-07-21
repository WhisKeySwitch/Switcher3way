## Context

The archived `windows-port-plan` chose the stack and mapped the APIs; the archived
`windows-win32-spike` proved them on real Windows and de-risked R2/R3/R5. This change builds the
shipping app. The heavy technical unknowns are settled — the open work is engineering: a real
detection core, offline dictionaries, a tray/settings UI, and (gating everything) signed
distribution. Findings that drive this design live in `windows-spike/FINDINGS.md`.

## Goals / Non-Goals

**Goals**
- Ship a signed EN/UK/RU auto + manual Windows app meeting `windows-platform-support`.
- Reuse the spike-proven Win32 patterns rather than re-deriving them.
- Make signing a phase-1 prerequisite (unsigned won't launch on EDR-managed devices).

**Non-Goals**
- No macOS changes. No shared cross-platform native core yet (re-port to C#, per archived D1;
  revisit a shared core only if drift becomes real — R7).
- No auto-update (the macOS fork disabled it; keep the Windows app offline + manually updated).

## Decisions

### M1 — Graduate the spike's proven Win32 patterns
Lift these from `windows-spike/` (then delete the throwaway): dead-key-safe `ToUnicodeEx` renderer
(clear→translate→flush), `GetKeyboardLayoutList` enumeration, `KeyClassifier` (letters+digits+OEM
buffer as token; space/enter/tab boundary; backspace pops; cursor keys reset), foreground switch
via `WM_INPUTLANGCHANGEREQUEST` with `AttachThreadInput` fallback **and switch confirmation**, hook
that **ignores `LLKHF_INJECTED`** events, and the release-wait/per-char `SendInput` rewrite.

### M2 — Re-port the detection core to C# (portable, no Win32)
Port `NWayResolver.resolve`/`manualPlan`, `passesSoftGates` + letter-core trimming, and
`AutoSwitchPolicy` (exceptions/pause/per-app/secure-context) into a UI- and OS-free assembly.
Unit-test against the macOS behavior: single-winner, ambiguity left alone (e.g. `там`), letter
core, punctuation re-render, 2-letter minimum, code-like gates.

### M3 — Offline validation via bundled Hunspell (archived D2)
Ship Hunspell + en/uk/ru dictionaries behind the letter-core validator interface. Do **not** rely
on Windows `ISpellChecker` (uk/ru language packs are frequently absent). Validate dictionary
quality against the macOS `NSSpellChecker` baseline on a representative word set.

### M4 — Signing: SignPath Foundation (OSS), sign exe + installer, timestamped
**Choice:** SignPath Foundation free OSS plan — an OV certificate whose private key stays on
SignPath's HSM; signing happens server-side via the `signpath/github-action-submit-signing-request`
GitHub Action. Sign **both** the apphost `.exe` and the installer; always RFC-3161 **timestamp**.
**Why:** free for MIT/public-repo OSS, globally available (no region gate), no hardware token to
manage. The spike proved this matters — an unsigned exe is blocked by Defender for Endpoint before
it runs, so signing is a launch prerequisite, not polish.
**Fallback:** Azure Trusted/Artifact Signing (~$10/mo) if SignPath OSS is declined — but individual
enrollment is **US/Canada only**, so it is a fallback, not the default.
**Trade-off:** signing is server-side/CI-bound (can't sign a local ad-hoc build without a request);
acceptable for release artifacts.

### M5 — Production build emits a signable exe (`UseAppHost=true`)
Unlike the spike (`UseAppHost=false`, run via the signed `dotnet` host to dodge the block), the
shipping app produces a real apphost `.exe` so users double-click it — which is exactly why it must
be signed (M4). Consider self-contained/single-file publish for a dependency-free install.

### M6 — Shell + installer (decide at implementation start)
WPF or WinForms shell with a `NotifyIcon` tray; MSIX (cleaner install/uninstall, stricter signing —
publisher must match the cert subject) or WiX MSI. Recorded as a first implementation task, not
pre-committed.

## Risks / Trade-offs

- **R4 dictionary coverage** — still open; validate Hunspell uk/ru against the macOS baseline early.
- **Signing pipeline** — SignPath approval + CI wiring is on the critical path; start it first.
- **R7 two-codebase drift** — keep the ported core small and spec-anchored; port behavior with tests.
- **R2 elevated windows** — medium-integrity app is inert in elevated apps (hook blind + inject
  refused). Ship "can't act here" feedback; consider an optional elevated mode later.
- **MSIX vs WiX** — MSIX signing is stricter (publisher identity binding); revisit under M6.

## Migration Plan

Additive: a new Windows solution alongside the macOS package. The throwaway `windows-spike/` is
removed once its patterns graduate (M1). Rollback = drop the Windows solution; the macOS app is
untouched. Phased delivery in `tasks.md`: signing/CI → portable core → dictionaries → live loop →
parity → packaging.

## Open Questions

- WPF vs WinForms vs WinUI 3 for the shell (tray + settings needs) — decide at M6.
- MSIX vs WiX as the primary installer — decide at M6.
- Trigger-key default on Windows (the spike used F9; pick a default that doesn't collide with common
  shortcuts and is present on laptops — the spike showed Pause/Break is often absent).
- Minimum supported Windows version (target Windows 10 21H2+ / Windows 11).

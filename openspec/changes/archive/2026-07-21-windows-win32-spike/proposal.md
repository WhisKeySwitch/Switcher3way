## Why

The archived `windows-port-plan` commits to a C#/.NET Windows port, but three of its risks
cannot be settled by planning — they either work on real Windows or they do not:

- **R3** — `ToUnicodeEx` mutates the kernel dead-key buffer; rendering buffered keystrokes
  through every installed layout could corrupt the user's live typing.
- **R5** — the Windows input language is per-foreground-thread, not global like macOS TIS, so
  switching the *foreground app's* layout is unproven.
- **R2** — `SendInput` cannot inject into higher-integrity (elevated) windows (UIPI); the port
  must at least *detect* this rather than silently fail.

This change runs a throwaway spike on this Windows machine to prove the end-to-end mechanism
(observe → render-all-layouts → switch → rewrite) before any architecture is committed. It
de-risks the port and produces a findings report that feeds the eventual MVP change.

## What Changes

- Add a **throwaway** C#/.NET console spike (not the shipped app, not the MVP codebase) under
  `windows-spike/` at the repo root, proving on real Windows:
  - `WH_KEYBOARD_LL` low-level hook buffering a word and detecting a word boundary (D3).
  - `GetKeyboardLayoutList` layout enumeration + `ToUnicodeEx`/`MapVirtualKeyEx` rendering the
    buffered keystrokes through **every** installed layout, using the documented dead-key
    flush pattern so live typing is not corrupted (D4, R3).
  - Foreground-app layout switch via `WM_INPUTLANGCHANGEREQUEST` with an `AttachThreadInput` +
    `ActivateKeyboardLayout` fallback (D5, R5).
  - Text rewrite via `SendInput`/`KEYEVENTF_UNICODE` with backspace-erase, plus detection of
    the elevated-window (UIPI) limitation rather than a silent failure (D6, R2).
- Add a short **findings report** recording what worked, what didn't, and any correction to
  the port's assumptions.
- No macOS changes, no MVP code. The durable Windows contract already lives in
  `specs/windows-platform-support/`; this spike validates its riskiest mechanisms and sharpens a
  single requirement based on what it proves.

## Capabilities

### New Capabilities
<!-- None. This is a throwaway feasibility spike; it introduces no durable capability. -->

### Modified Capabilities
- `windows-platform-support`: sharpen "Switch the foreground application's layout" to require
  confirming the switch took effect and falling back to an alternative mechanism when the
  primary request does not — the per-thread reality (R5) this spike exists to prove.

## Impact

- **New throwaway code**: `windows-spike/` (a standalone .NET 8 console project). Explicitly
  not the MVP; intended to be discarded or cannibalized once the mechanism is proven.
- **New dependency (dev only)**: .NET 8 SDK (installed on this machine).
- **No impact** on the macOS app, its build, signing, or release flow.
- **Follow-up**: findings feed the future `windows-mvp` change (roadmap phases 1, 3, 4, 5, 6).

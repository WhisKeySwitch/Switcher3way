## Context

This spike proves the Win32 mechanics the `windows-port-plan` (archived) assumes, on real
Windows, before any architecture is committed. It is throwaway: a single-project .NET 8 console
app under `windows-spike/`, P/Invoking Win32. It deliberately does **not** pull in Hunspell,
detection logic, tray UI, or settings — those belong to the future MVP. The only question this
answers is: *can a normal user-process observe keystrokes, render them through every installed
layout without corrupting live typing, switch the foreground app's layout, and rewrite text?*

## Goals / Non-Goals

**Goals**
- Prove D3/D4/D5/D6 end-to-end and confirm the dead-key flush (R3), per-thread switch (R5), and
  UIPI limitation (R2) behave as the plan assumes.
- Produce a findings report that either green-lights the C#/.NET stack or flags a needed change.

**Non-Goals**
- No N-way detection, no dictionaries, no exception policy, no tray/settings UI, no signing.
- Not the MVP codebase; correctness of the *mechanism* matters, not code quality or coverage.
- No macOS changes; no changes to the durable `windows-platform-support` spec.

## Decisions

### S1 — One throwaway .NET 8 console project, P/Invoke only
A single `windows-spike/windows-spike.csproj` (`net8.0-windows`, `AllowUnsafeBlocks`,
`<Nullable>enable`). All Win32 via `[DllImport]`. No NuGet deps. Keeps the spike self-contained
and disposable.

### S2 — Hook on a dedicated STA thread with a message pump
`WH_KEYBOARD_LL` requires a running message loop to deliver callbacks. The spike installs the
hook on its own thread that runs `GetMessage`/`TranslateMessage`/`DispatchMessage`, so callbacks
fire while the user types into other apps. The callback stays lean: it appends virtual-key +
scancode to a buffer and, on a boundary key (space/enter/punctuation), signals the main thread
to evaluate. Heavy work never runs inside the hook (D3 note).

### S3 — Render through every layout with a dead-key-safe `ToUnicodeEx` sequence
For each `HKL` from `GetKeyboardLayoutList`, translate each buffered scancode with `ToUnicodeEx`.
Because `ToUnicodeEx` mutates the per-layout dead-key state, the spike uses the documented
clear-then-translate pattern: call it against a spare key first to drain any pending dead key,
translate the real keys, then flush again — so the kernel buffer is left clean and live typing
is unaffected (R3). This is the single riskiest thing the spike must demonstrate.

### S4 — Switch the foreground layout, not the caller's thread
`ActivateKeyboardLayout` alone only affects the calling thread. The spike targets the foreground
window: `GetForegroundWindow` → `PostMessage(WM_INPUTLANGCHANGEREQUEST, INPUTLANGCHANGE_FORWARD,
hkl)`. Fallback: `AttachThreadInput` to the foreground thread, `ActivateKeyboardLayout`, detach.
The spike reports which path took effect (R5).

### S5 — Rewrite via `SendInput` Unicode, and *detect* UIPI failure
Erase with N synthesized backspaces, insert the corrected string as `KEYEVENTF_UNICODE` events.
`SendInput` returns the number of events injected; when the foreground window is higher-integrity
the count is short / injection is refused. The spike compares requested vs. injected and, on a
mismatch, reports "protected target" rather than claiming success (R2). No clipboard path in the
spike — that's an MVP concern.

### S6 — Interactive, observable, manual verification
The spike is a console harness the operator drives by typing in a real app (Notepad, browser,
elevated PowerShell). It logs each stage (`buffered`, `rendered[layout]=...`, `switched via ...`,
`rewrote N chars` / `PROTECTED`) to the console so a human can confirm behavior. Automated tests
are out of scope for a throwaway spike; the deliverable is the findings report.

## Risks / Trade-offs

- **The hook needs a message pump** — a naive install without a loop silently receives no
  callbacks. Mitigated by S2.
- **`ToUnicodeEx` statefulness** is the crux (R3); if the flush pattern proves unreliable the
  finding is itself the valuable output — it would push the MVP toward a different renderer.
- **Antivirus may flag a keystroke hook** even in a spike; run locally, document if it fires
  (foreshadows R1 for the real app).
- **Throwaway drift**: the spike is not the MVP and must not be treated as its foundation
  wholesale; only proven patterns graduate.

## Migration Plan

None — additive throwaway code in a new directory. Rollback = delete `windows-spike/`. Findings
graduate into the future `windows-mvp` change; the spike directory itself can then be removed.

## Open Questions

- Does the S3 flush pattern hold across a dead-key-heavy layout (e.g., international layouts), or
  only for EN/UK/RU? (Test with whatever layouts are installed on this machine.)
- Does `WM_INPUTLANGCHANGEREQUEST` behave the same in Win32, UWP, and Electron targets, or is the
  `AttachThreadInput` fallback needed for some? (Spike tests whatever apps are available.)
- Is the UIPI short-injection signal reliable enough to surface to the user, or is a UIA probe
  needed? (Deferred to MVP if the `SendInput` return count proves ambiguous.)

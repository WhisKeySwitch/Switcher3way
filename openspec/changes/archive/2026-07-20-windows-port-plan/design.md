## Context

Switcher3way (macOS) is a SwiftPM/AppKit app. Its behavior splits into two layers:

- **Platform-independent detection logic** (~600–800 lines): `NWayResolver.resolve`/`manualPlan` (render keystrokes through every installed layout, validate the letter core, switch only on a single unambiguous winner), `LayoutDetector.passesSoftGates` + letter-core trimming, and the exception/pause/per-app policy in `AutoSwitchPolicy`.
- **macOS OS bindings**: CGEvent tap (`KeyboardMonitor`), TIS input-source control (`LayoutSwitcher`), `UCKeyTranslate` (`DynamicKeyMapping`), `NSSpellChecker` (`Dict`), CGEvent synthesis + clipboard (`TextConverter`), `NSStatusItem`/AppKit UI, `NSWorkspace` frontmost-app, and TCC permissions.

A Windows build must reproduce the detection *behavior* while replacing every OS binding. This document records the stack, the per-module API mapping, and the risky decisions. It is a plan; no Windows code is produced by this change.

## Goals / Non-Goals

**Goals:**
- Choose a target stack and justify it.
- Map each macOS subsystem to a concrete Windows API.
- Resolve, or explicitly defer, the high-risk decisions (dictionary source, hook type, layout-switch mechanism, dead-key handling, secure-field handling, signing).
- Preserve the app's precision-first, N-way, EN/UK/RU detection semantics.

**Non-Goals:**
- Writing Windows code or scaffolding a project.
- Refactoring the macOS app (portable-core extraction is noted as future work, not done here).
- Feature parity beyond what the capability spec requires; installer artwork, store distribution, and auto-update are out of scope for the initial plan.

## Decisions

### D1 — Stack: C#/.NET (WinForms or WPF shell + P/Invoke)
**Choice:** C#/.NET desktop app; tray via `NotifyIcon`; Win32 via P/Invoke; WinRT interop where useful.
**Why:** Mature tray + settings UI, first-class Win32 interop, and a built-in spellchecker API. Fast path to a working MVP.
**Alternatives:** Rust (excellent for hooks/cross-platform core, weaker/heavier UI story) — attractive if a *shared* engine is wanted later; C++/Win32 (maximum control, most effort); Swift-on-Windows (rejected — no viable GUI/tray story).

### D2 — Dictionaries: bundle Hunspell, do not rely on `ISpellChecker`
**Choice:** Ship Hunspell + en/uk/ru dictionaries with the app.
**Why:** Detection *depends entirely* on offline validation. Windows `ISpellChecker` only exposes a language if its spellcheck feature/language pack is installed, and uk/ru are frequently absent — behavior would silently degrade per machine. Bundling makes results deterministic and matches the macOS baseline coverage. It also becomes the natural shared validation layer if a cross-platform core is built later.
**Alternatives:** `ISpellChecker` (rejected as primary due to coverage; acceptable as an optional fallback).
**Trade-off:** App size grows by the dictionary payload; dictionaries need occasional updates.

### D3 — Keystroke observation: low-level keyboard hook
**Choice:** `SetWindowsHookEx(WH_KEYBOARD_LL)`.
**Why:** Global, before-focus keystroke visibility with virtual-key + scancode, matching what `KeyboardMonitor` needs to buffer words and detect boundaries.
**Alternatives:** Raw Input (no easy per-layout translation, no suppression); a driver-level filter (overkill, signing/deployment burden).
**Note:** The hook callback must be fast and non-blocking; heavy work (dictionary lookups, UI) is marshalled off the hook thread.

### D4 — Per-layout rendering: `ToUnicodeEx` + `MapVirtualKeyEx`
**Choice:** Translate each buffered key through each candidate layout's `HKL` with `ToUnicodeEx`.
**Why:** Direct analogue of `UCKeyTranslate` — the mechanism that lets the app see "what these keystrokes would be in layout X."
**Risk handling:** `ToUnicodeEx` mutates the kernel dead-key buffer; calls must use the documented flush/clear sequence so the user's live typing and dead keys are not corrupted (see R3).

### D5 — Layout switching: post `WM_INPUTLANGCHANGEREQUEST` to the foreground window
**Choice:** Enumerate layouts with `GetKeyboardLayoutList`; switch by posting `WM_INPUTLANGCHANGEREQUEST` to the foreground window (fallback: `ActivateKeyboardLayout` on the attached input thread via `AttachThreadInput`).
**Why:** Windows input language is per-foreground-thread, not global like macOS TIS. Posting the change request to the foreground window is the supported way to change the active layout of the app the user is typing in.
**Alternatives:** `ActivateKeyboardLayout` alone (affects only the caller's thread — insufficient).

### D6 — Text rewrite: `SendInput` with `KEYEVENTF_UNICODE`
**Choice:** Erase with synthesized backspaces, insert corrected text as Unicode via `SendInput`; clipboard paste as the selection/fallback path.
**Why:** Mirrors `TextConverter.beginCycle` (backspace + Unicode insert) and its clipboard fallback.
**Constraint:** `SendInput` cannot inject into higher-integrity (elevated) windows from a normal process (see R2).

### D7 — Foreground app + secure-context exclusions
**Choice:** Identify the active app via `GetForegroundWindow` → `GetWindowThreadProcessId` → `QueryFullProcessImageName` (match by exe name/path). Detect password fields via UI Automation (`IsPassword` / control type) on a best-effort basis; keep a denied-apps list as the primary guard.
**Why:** Reproduces `AutoSwitchPolicy` denied-apps and the secure-input veto. Windows has no direct `IsSecureEventInputEnabled` equivalent, so the denied-apps list carries more weight.

### D8 — Signing/packaging: Authenticode + MSIX/WiX
**Choice:** Authenticode-sign the binaries; distribute via MSIX (preferred) or a WiX MSI; publish alongside the existing GitHub release flow.
**Why:** A keystroke-rewriting tool needs signature-backed trust to survive SmartScreen and reduce AV friction (see R1).

## Risks / Trade-offs

- **R1 — AV/SmartScreen flags a keystroke-rewriting tool as a keylogger.** → Authenticode signing, submit to Microsoft for reputation, document the SmartScreen "More info → Run anyway" path, and provide VirusTotal transparency; expect initial false positives.
- **R2 — `SendInput` cannot fix text in elevated/admin apps (UIPI).** → Document the limitation; optionally offer an elevated mode; do not silently fail — surface that the target app is protected.
- **R3 — `ToUnicodeEx` corrupts live dead-key state.** → Use the known translate-then-flush pattern; unit-test against dead-key layouts before wiring into the live hook.
- **R4 — Offline uk/ru coverage.** → Resolved by D2 (bundle Hunspell); validate dictionary quality against the macOS `NSSpellChecker` baseline on representative words.
- **R5 — Per-thread layout model differs from macOS.** → D5's foreground-window request; test across Win32, UWP, and Electron targets, which handle input languages differently.
- **R6 — Weaker password-field privacy than macOS secure input.** → D7 best-effort detection + denied-apps default list (browsers' password managers, credential dialogs).
- **R7 — Two parallel codebases drift.** → Keep the detection algorithm small and spec-anchored; consider a shared Rust/native core only if drift becomes real (deferred).

## Migration Plan

Not a deployment/migration in the running-system sense — this change ships planning artifacts only. Rollback is trivial (delete the change). The downstream implementation is phased in `tasks.md`: portable-core identification → Win32 plumbing spike (hook + `ToUnicodeEx` + `SendInput`) → dictionary integration → MVP (EN/UK/RU auto + manual, tray) → parity (settings, exceptions, per-app memory, localization) → signing/installer.

## Open Questions

- WinForms vs. WPF vs. WinUI 3 for the shell — decide at implementation start based on tray/settings needs and .NET version.
- MSIX vs. WiX MSI as the primary distribution format (MSIX has cleaner install/uninstall but stricter packaging/signing).
- Whether to invest in a shared cross-platform core (Rust) now, or keep two codebases and revisit after the Windows MVP proves the design.
- Minimum supported Windows version (target Windows 10 21H2+ / Windows 11; confirm `ISpellChecker`/UIA/MSIX baselines).
- Trigger-key model on Windows (macOS uses a modifier tap) — pick a default that doesn't collide with common Windows shortcuts.

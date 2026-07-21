## 1. Spike project scaffold

- [x] 1.1 Create `windows-spike/windows-spike.csproj` (`net8.0-windows`, `AllowUnsafeBlocks`, nullable enabled, no NuGet deps) and a `Program.cs` console entry point
- [x] 1.2 Add the Win32 P/Invoke surface (`Native.cs`): `SetWindowsHookEx`/`UnhookWindowsHookEx`/`CallNextHookEx`, `GetKeyboardLayoutList`, `ToUnicodeEx`, `MapVirtualKeyEx`, `GetForegroundWindow`/`GetWindowThreadProcessId`, `PostMessage`/`AttachThreadInput`/`ActivateKeyboardLayout`/`GetKeyboardLayout`, `SendInput`, `QueryFullProcessImageName`
- [x] 1.3 Confirm the project builds with `dotnet build` (proves the toolchain end-to-end)

## 2. Keystroke observation (D3 / R-hook)

- [x] 2.1 Install `WH_KEYBOARD_LL` on a dedicated thread with a `GetMessage` pump so callbacks fire while typing in other apps
- [x] 2.2 Buffer virtual-key + scancode per keystroke; detect a word boundary (space/enter/tab/punctuation) and hand the completed buffer to the evaluator off the hook thread
- [x] 2.3 Log `buffered: <keys>` on each boundary and confirm it fires from a real target app (Notepad) — CONFIRMED live (operator: ghbdtn→привет, cyjdf→снова, db,fxnt→вибачте). Surfaced+fixed the comma bug (punctuation keys are letters in Cyrillic; now buffered as part of the token)

## 3. Per-layout rendering (D4 / R3 — the crux)

- [x] 3.1 Enumerate installed layouts with `GetKeyboardLayoutList`; log each HKL and its language id — VERIFIED (self-test: en-US, ru-RU, uk-UA)
- [x] 3.2 Render the buffered scancodes through each HKL with `ToUnicodeEx`, using the clear-then-translate-then-flush dead-key pattern — VERIFIED (self-test: G,H,B,D,T,N → ghbdtn / привет / привет)
- [x] 3.3 Verify live typing and dead keys are NOT corrupted after rendering — repeat-render check passed AND live typing stayed clean across a full interactive session of interleaved words + conversions (EN/UK/RU use few dead keys; residual risk low, revisit for diacritic-heavy layouts)

## 4. Foreground layout switching (D5 / R5)

- [x] 4.1 Switch the foreground app's layout via `PostMessage(WM_INPUTLANGCHANGEREQUEST, INPUTLANGCHANGE_FORWARD, hkl)`
- [x] 4.2 Add the `AttachThreadInput` + `ActivateKeyboardLayout` fallback and detect (via `GetKeyboardLayout` of the foreground thread) which path actually took effect
- [x] 4.3 Log `switched via <primary|fallback|none>` and confirm continued typing uses the new layout — CONFIRMED live (`switched via Primary` on every conversion; N-way cycle ru→uk→original works)

## 5. Text rewrite + UIPI detection (D6 / R2)

- [x] 5.1 Erase the buffered word with synthesized backspaces and insert the corrected string via `SendInput`/`KEYEVENTF_UNICODE`, preserving the trailing boundary char
- [x] 5.2 Compare requested vs. `SendInput`-injected event count; against an elevated window, confirm the short/refused injection is detectable and log `PROTECTED` instead of claiming success — count-check implemented; R2 characterized: the gate is process integrity (elevated spike injects everywhere; non-elevated spike is inert in elevated windows — hook blind + inject refused)
- [x] 5.3 Confirm a normal rewrite round-trips in Notepad (type a wrong-layout word, trigger, see it corrected) — CONFIRMED live (clean round-trip after fixing hook re-entrancy/timing; trailing space preserved)

## 6. Findings report

- [x] 6.1 Write `windows-spike/FINDINGS.md`: per-risk verdict (R2 UIPI, R3 dead-key, R5 switch+fallback), layouts/apps tested, and corrections to the port's assumptions (comma/whole-token bug; MDE blocks unsigned exe)
- [x] 6.2 State the go/no-go for the C#/.NET stack and list which proven patterns graduate to the future `windows-mvp` change — GO; patterns + priority order recorded in FINDINGS.md

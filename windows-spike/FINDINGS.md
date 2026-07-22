# Windows Win32 spike — findings

> **Graduated (2026-07-22).** The spike's proven Win32 patterns — dead-key-safe `ToUnicodeEx`
> renderer, `GetKeyboardLayoutList` enumeration, `KeyClassifier`, `WH_KEYBOARD_LL` hook (ignoring
> injected input), foreground switch with confirm + fallback, and per-char `SendInput` rewrite —
> now live in the production app at `windows/src/Switcher3way.App/` (windows-mvp phase 4), wired to
> the tested `Switcher3way.Core` engine and real Hunspell dictionaries. The throwaway spike **code**
> has been removed; this findings record is retained for the rationale and the verified results.

Throwaway feasibility spike for the Switcher3way Windows port. Status as of the first run on
this Windows 11 machine. Verdicts are split into **proven here** (ran non-interactively) and
**pending interactive run** (need a human typing into real apps — see "How to finish" below).

## Environment

- Windows 11 Pro (26200), .NET 8.0.423 SDK.
- Installed layouts: `en-US`, `ru-RU`, `uk-UA` — exactly the three target languages.
- App-control policy is NOT enforcing: AppLocker Exe/Dll = **AuditOnly** (only a disabled "Dummy
  Rule"), WDAC user-mode CI = 0, Smart App Control = off, SRP = none.
- **Microsoft Defender for Endpoint (MDE) is active** — the `Sense` service is Running — and
  **Controlled Folder Access is on**. This is a managed device with enterprise EDR.

## Proven here (self-test, `dotnet windows-spike.dll selftest` — 17/17 assertions pass, exit 0)

| Mechanism | Decision | Result |
|-----------|----------|--------|
| Layout enumeration (`GetKeyboardLayoutList` + LANGID) | D4 | ✅ 3 layouts resolved to en-US / ru-RU / uk-UA |
| Per-layout rendering (`ToUnicodeEx`/`MapVirtualKeyEx`) | D4 | ✅ keys G,H,B,D,T,N → `ghbdtn` / `привет` / `привет` |
| Whole-token buffering incl. OEM punctuation | — | ✅ `d,b,COMMA,f,x,n,t` → `вибачте` (the ',' key is 'б') |
| Shift fidelity (per-key shift state in `ToUnicodeEx`) | D4 | ✅ Shift+G,h,b,d,t,n → `Привет` (real capital П) |
| Dead-key buffer safety on repeat render (**R3**) | S3 | ✅ pass1 == pass2 for all layouts (no state leak across renders) |
| Buffer-reset classification | — | ✅ asserted: letters+digits+OEM=buffer, space=boundary, ⌫=pop, shift=modifier, arrows/F-keys=reset |
| Global hook fires from a real app (**live**) | D3 | ✅ operator confirmed buffering in Notepad (task 2.3) |

Detection-relevant note: `ru-RU` and `uk-UA` both render `привет` for that key sequence — the
cross-Cyrillic ambiguity the N-way precision-first resolver exists to arbitrate via dictionaries.
Confirms the Windows renderer feeds the same ambiguity the macOS detector already handles.

Fidelity hardening added after the first run (all covered by asserts — self-test now 17/17):
- The word buffer now records the **real hardware scancode** from the hook and the **physical
  shift state** (`GetAsyncKeyState`) per key, instead of rendering everything unshifted with a
  synthesized scancode — so capitals and shifted punctuation render correctly.
- Buffer-reset guards moved into a pure, unit-tested `KeyClassifier`; **backspace now pops the
  last key** (in-place edit) rather than discarding the whole word; bare modifiers keep the
  buffer; cursor-movement/editing keys reset it.

### Live-run finding: punctuation keys are LETTERS in Cyrillic (fixed)

Confirmed interactively (hook fires from Notepad — task 2.3): the operator typed `db,fxnt`
intending `вибачте` (UK), but the initial classifier treated the comma key as a buffer *reset*,
so it discarded `db` and only kept `fxnt` → `ачте`. On the ЙЦУКЕН layout the physical `,` key is
`б` (and `.`→`ю`, `[`→`х`, `;`→`ж`, `'`→`э`, `` ` ``→`ё`). **The buffer must keep OEM
punctuation/digit keys as part of the token, not treat them as separators** — matching the macOS
app's "re-render the whole token including punctuation keys." Fixed and asserted: physical keys
`d,b,COMMA,f,x,n,t` now render `вибачте` (uk + ru). Only space/enter/tab end a word; only cursor
movement/editing keys reset the buffer.

Downstream MVP note: because a trailing `.`/`,` may be either real punctuation or a Cyrillic
letter, the detector's letter-core trimming (already in the macOS `NWayResolver`) is what decides;
the Windows buffer just must not drop those keys before the detector sees them.

Shift detection confirmed accurate (was flagged as an open question): a live word rendered
`ghbdtn?` with **lowercase letters but a shifted `?`** — proving per-key `GetAsyncKeyState` shift
capture is correct (Shift held only for `?`). The earlier capital-first words were genuine Shift
presses, not a bug.

Live confirmations from the second run: comma/whole-token buffering works in Notepad
(`db,fxnt`→`Вибачте`, `cj,frf`→`собака`); a valid English word case appeared (`hi,`→`Ршб`) that
the detector — not the spike — would leave unconverted.

## Interactive-run results (all confirmed by operator)

Hook + buffering + live rendering are **confirmed** (task 2.3). Foreground layout switch is
**confirmed** too:

- **Foreground layout switch (D5 / R5)** — ✅ confirmed live: repeated conversions all reported
  `switched via Primary` in Notepad, and continued typing used the switched layout. The per-thread
  `WM_INPUTLANGCHANGEREQUEST` mechanism works; the `AttachThreadInput` fallback was not needed here.

### Live-run bug: SendInput rewrite corrupted the text (fixed, pending re-verify)

Second interactive run: the switch worked every time, but the rewrite garbled the output — a word
came out as the **last character repeated** (`ghbdtn`→`nnnnnn`, `привет`→`тттттт`), even though the
console showed the correct target string. Root causes and fixes applied:

1. **Our global hook re-processed our own synthesized keystrokes.** SendInput events are visible to
   `WH_KEYBOARD_LL`. Fix: ignore events flagged `LLKHF_INJECTED`.
2. **F9 auto-repeat piled up overlapping conversions.** Fix: a `_converting` re-entrancy guard drops
   F9 while a conversion is in flight; the rewrite also **waits for F9 to be physically released**
   before injecting (a still-held trigger key was a prime suspect for the repeated-char artifact).
3. **Injection hardened**: per-character `SendInput` (down+up), a settle delay after the erase, and a
   small gap between characters so rapid identical chars aren't coalesced/autorepeated.

Second-order fix after the "mixed" run: the manual trigger now converts the **in-progress word**
(caret right after it → clean erase) or, if the word was finished with a space, erases the word
**plus** that space and re-adds it. It is also **single-shot** — buffers clear after a conversion,
so repeated F9 no longer toggles ru↔en and stacks edits (that flip was a spike artifact; the real
N-way candidate cycle is MVP work).

### Live-run: N-way manual cycle + rewrite — confirmed

After the fixes, the operator confirmed the full manual flow in Notepad: typing `ghbdsn` then
tapping F9 cycled **ru `привыт` → uk `привіт` → original `ghbdsn`**, each step switching the layout
(`switched via Primary`) and rewriting the text **cleanly** (no corruption, space preserved). Typing
a new word resets the cycle. This exercises D5/D6 and the N-way manual-trigger semantics end to end.

### R2 / UIPI — characterized (integrity level is the gate)

Rewriting into an **elevated** Notepad "worked the same" — because the spike itself was run from an
**elevated** terminal, so it injects at the same integrity level and UIPI does not apply. The real
limitation is the non-elevated case:

- **Spike elevated → works everywhere**, including elevated apps. (This is the "optional elevated
  mode" mitigation noted for R2.)
- **Spike non-elevated → inert in elevated windows**: UIPI blocks both directions — the
  `WH_KEYBOARD_LL` hook does not even receive keystrokes typed into a higher-integrity window (no
  `buffered:` line), and `SendInput` into it is refused. The spike's requested-vs-injected count
  check is a backstop for the inject side, but in practice the app is *blind* there first.

MVP takeaway (D7/R2): document the elevated-window limitation, and — because the medium-integrity
app cannot observe or fix text in elevated apps — either ship an optional elevated mode or clearly
surface "can't act in this window." Matches the macOS secure-input veto in spirit.

Dead-key safety (R3): no dedicated diacritic sequence was run, but live typing stayed clean across
many interleaved words and conversions for the whole session, and the self-test proves render
stability. EN/UK/RU make little use of dead keys, so residual R3 risk is low; revisit if a
diacritic-heavy layout is added.

## Environment blocker worth recording — a managed ASR rule (not signing)

The freshly built **unsigned apphost exe could not be launched**: `CreateProcess` returned "Access
is denied", reproduced in a normal **elevated** terminal. Initial investigation attributed this to
Microsoft Defender for Endpoint (the `Sense` service was running). **Further testing corrected the
root cause:** a managed **Attack Surface Reduction** rule — *"Block executable files from running
unless they meet a prevalence, age, or trusted-list criterion"*
(`01443614-cd74-433a-b99e-2ecdc07bfc25`), pushed via device management (Defender Exploit Guard event
1121, "blocked by your IT administrator"). Offboarding MDE did **not** lift it (the ASR rule is
managed separately); only disabling that rule after the device was unenrolled unblocked launch.

**Signing implication (verified by experiment).** This rule evaluates **Microsoft-cloud prevalence**,
not local signature validity:
- A **self-signed** cert — even with a `Valid` signature and the cert trusted in the local Root
  store — is **still blocked** by the rule.
- With the rule disabled, an **unsigned** exe launches fine (so does a self-signed one).

So signing is **not a dev-launch prerequisite** — it is a **distribution** concern. On an unmanaged
machine no signing is needed; end-user machines that enforce this ASR rule (common in enterprises)
or SmartScreen will block a low-prevalence exe until it earns Microsoft-cloud prevalence (via
downloads) or is signed with an **EV** certificate. A self-signed cert never satisfies either.

**Dev workarounds (verified):**
1. Run via the signed **`dotnet` host** (`dotnet …\windows-spike.dll`) — works regardless of the ASR
   rule (the spike ships `<UseAppHost>false</UseAppHost>`, so `dotnet run` uses this path).
2. On your own machine, **disable the ASR rule** (or add an ASR exclusion); on a managed device, ask
   IT. See `signing/README-windows.md`.

## How to finish the spike (operator steps)

Run at a real desktop (the interactive mode needs live typing). With `UseAppHost=false` this now
runs through the signed `dotnet` host, so no exe launch and no MDE block:

```
cd windows-spike
dotnet run                 # interactive (runs via the dotnet host; no unsigned exe to block)
```

1. Open Notepad. Type `ghbdtn ` (with trailing space). Expect `buffered: GHBDTN` and
   `rendered[ru-RU] = "привет"`, `rendered[uk-UA] = "привет"`.  → task 2.3 ✅ confirmed
2. Type `ghbdtn` (no space), then press **F9**. Expect `switched via Primary` (or `Fallback`) and
   `rewrote OK`, the Notepad text to become `привет`, and continued typing to use the switched
   layout. → tasks 4.3, 5.3  *(F9 is swallowed by the hook, so it won't type into the app)*
3. Type a dead-key/diacritic sequence right after a conversion; confirm it is not corrupted. → task 3.3
4. Repeat step 2 against an **elevated** window (e.g. Notepad "Run as administrator"). Expect
   `PROTECTED` instead of a claimed success. → task 5.2 (UIPI), R2

## Go / no-go — **GO** on the C#/.NET stack

Every mechanic the plan depends on now works on real Windows, confirmed end to end:

| Risk / decision | Verdict |
|---|---|
| D4 per-layout `ToUnicodeEx` rendering | ✅ works (en/ru/uk), incl. shift + OEM punctuation-as-letters |
| R3 dead-key buffer safety | ✅ stable across renders and a full live session (low residual risk) |
| D5 / R5 foreground per-thread layout switch | ✅ `WM_INPUTLANGCHANGEREQUEST` (Primary) reliable; fallback in place |
| D6 text rewrite (`SendInput` backspace+Unicode) | ✅ clean round-trip after fixing hook re-entrancy + timing |
| N-way manual cycle (…→ru→uk→original) | ✅ confirmed live |
| R2 / UIPI (elevated windows) | ⚠️ understood: elevated app needs elevated mode; non-elevated is inert there |
| R1 / D8 signing | ⚠️ refined: the dev-machine block was a managed **ASR "block low-prevalence exe" rule**, not a signing gap — signing is a **distribution** concern (SmartScreen + enterprise ASR); self-signed does not satisfy it, EV/prevalence does |

**Recommendation:** proceed to the `windows-mvp` change (roadmap phases 1, 3, 4, 5, 6). Graduate
these proven patterns: layout enumeration, dead-key-safe `ToUnicodeEx` rendering, the
`KeyClassifier` buffer/whole-token rules, foreground switch-with-confirm, injected-input-ignoring
hook, and the release-wait/per-char `SendInput` rewrite. Treat as MVP-critical, in priority order:
**(1)** Authenticode signing from day one (R1/D8 — the app won't launch on managed devices unsigned);
**(2)** the real detection engine (Hunspell dictionaries + N-way resolver) — the spike only renders,
it does not decide; **(3)** an elevated-window story (R2). The spike's throwaway harness should be
cannibalized for patterns, then removed.

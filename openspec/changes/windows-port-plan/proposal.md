## Why

Switcher3way is macOS-only, but the wrong-layout-typing problem it solves (EN/UK/RU) is at least as common on Windows. Before committing engineering effort to a port, we need an agreed plan: the target stack, how each macOS-specific subsystem maps to a Windows equivalent, the decisions that carry real risk (offline dictionary coverage, antivirus/SmartScreen, injection into elevated apps), and a phased task list. This change is **planning and specification only** — it produces the architecture, the capability requirements the Windows build must satisfy, and an ordered task plan. No Windows code is written here.

## What Changes

- Add a new capability spec, `windows-platform-support`, stating the platform-independent requirements a Windows build must meet: global keystroke observation, per-layout keycode↔character rendering, offline word validation, layout switching for the foreground application, text rewrite, tray UI, and per-app/secure-context exclusions — while preserving the existing N-way, precision-first detection behavior.
- Add `design.md` capturing the recommended stack (C#/.NET), a macOS→Windows API mapping per module, and the key decisions with rationale (Hunspell vs. `ISpellChecker`, hook type, layout-switch mechanism, dead-key handling, signing).
- Add `tasks.md` with a phased plan (portable-core extraction → Win32 plumbing → MVP → parity → packaging/signing).
- No changes to the existing macOS capabilities or code. The Windows implementation is intended as a parallel codebase; the shared, platform-independent detection logic is called out for reuse but not refactored in this change.

## Capabilities

### New Capabilities
- `windows-platform-support`: platform-independent requirements and constraints for a Windows build of Switcher3way — keystroke observation, layout enumeration/switching, per-layout rendering, offline validation, text rewrite, tray UI, and exclusion policy — that together reproduce the app's N-way detection behavior on Windows.

### Modified Capabilities
<!-- None. Existing macOS capabilities are unchanged; this change adds a parallel platform capability and planning artifacts only. -->

## Impact

- **Docs/specs only in this change**: new `openspec/changes/windows-port-plan/` artifacts and one new capability spec on archive.
- **Future code (out of scope here)**: a new Windows codebase (proposed C#/.NET), bundled Hunspell dictionaries + data, Authenticode signing, and an MSIX/WiX installer.
- **Risk areas to resolve during design**: offline uk/ru dictionary availability, antivirus/SmartScreen reputation for a keystroke-rewriting tool, `SendInput` into higher-integrity (elevated) windows, the per-thread Windows layout-switch model, and `ToUnicodeEx` dead-key statefulness.
- **No impact** on the shipping macOS app, its build, signing, or release flow.

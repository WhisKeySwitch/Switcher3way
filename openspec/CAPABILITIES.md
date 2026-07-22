# Capabilities

This project currently centers on eleven capabilities that are reflected in the implementation and the generated specs.

## 1. Manual conversion and undo
Converts the most recently typed word or selected text between keyboard layouts and reverses the previous conversion when invoked again.

## 2. Automatic conversion on word boundaries
Evaluates the typed word at word boundaries and performs conversion only when the input passes the configured soft gates and exception rules.

## 3. Layout switching and language detection
Enumerates installed input sources, resolves the target layout from the current input, and switches the active layout through the macOS input-source API.

## 4. Per-app layout memory
Remembers the layout associated with each application and restores it when focus returns to that application.

## 5. Settings and exception management
Persists trigger preferences, auto-conversion behavior, layout pair settings, and the exception lists for apps and words.

## 6. Permission and startup lifecycle
Checks the required macOS permissions on launch, synchronizes login-item state, and starts or reconfigures monitoring as needed.

## 7. Layout change feedback
Optional sensory feedback on layout changes: a floating flag badge shown next to the text caret (with Accessibility-based caret resolution and secure-input suppression) and a one-shot audio cue on the first keystroke after a switch. Both off by default.

## 8. Interface localization
Localizes all UI strings into 16 languages with a guaranteed English fallback; the interface language follows the system locale unless the user forces one, and the menu re-localizes on change.

## 9. Menu bar UI and status icon
The menu-bar status item whose emoji-flag icon live-tracks the active layout (including system-initiated switches), plus the menu of feature toggles, version info, and quit.

## 10. Diagnostics and debug logging
Opt-in rotating file log (5 MB cap) with an Advanced-tab toggle, path display, and reveal-in-Finder action.

## 11. Software updates
Checks the fork's own public releases repo (daily, toggleable; plus a menu item), notifies with release notes, and installs one-click verified updates: sha256 against the release's `version.json` manifest asset plus a same-certificate codesign gate, in-place swap with rollback, relaunch. Can never offer an upstream rashn/RuSwitcher build — the source repo is the fork's.

## Planned (spec exists, not yet implemented)
**Windows platform support** — a target contract for a future Windows port of the app, capturing the platform-independent requirements (keystroke observation, layout enumeration/switching, per-layout rendering, offline validation, N-way detection semantics, text rewrite, tray UI, exclusion policy, signed offline distribution). The spec lives at `specs/windows-platform-support/`; the planning artifacts (design + API mapping + phased roadmap) are archived under `changes/archive/2026-07-20-windows-port-plan/`. A throwaway C#/.NET **feasibility spike** (`windows-spike/`, archived under `changes/archive/2026-07-21-windows-win32-spike/`) has since proven the Win32 mechanics on real Windows — hook, per-layout `ToUnicodeEx` rendering, foreground layout switch, `SendInput` rewrite, and the N-way manual cycle — verdict **GO** (see `windows-spike/FINDINGS.md`); the key blocker is Authenticode signing (Defender for Endpoint blocks the unsigned exe). No production/MVP Windows code exists yet.

## Explicitly out of scope (disabled in this fork)
**Updating from upstream** — the upstream updater was deleted at fork time so stock rashn/RuSwitcher releases could never clobber the fork. The fork's own updater (capability 11, July 2026) is scoped exclusively to `WhisKeySwitch/switcher3way-releases`; upstream remains out of the update path by design.

# Capabilities

This project currently centers on ten capabilities that are reflected in the implementation and the generated specs.

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

## Explicitly out of scope (disabled in this fork)
**Update checking** — removed entirely (July 2026 cleanup; `UpdateChecker.swift` deleted). Auto-update was disabled at fork time so upstream releases could not clobber the fork, then the dormant pipeline was deleted. No spec exists for it.

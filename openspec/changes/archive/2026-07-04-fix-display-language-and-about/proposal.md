# Proposal: fix-display-language-and-about

## Why

Two follow-ups from the modernize-ui visual pass. (1) The menu status header, the manual-pair layout popups, and the exceptions app list show names in the **macOS system language** (e.g. Russian) even when the app's interface language is set to English — `kTISPropertyLocalizedName` and `FileManager.displayName` localize per system, not per app, so the UI comes out mixed-language. (2) The About tab content is left-aligned; it should be centered.

## What Changes

- **Display names follow the app's interface language.** When the app's effective interface language matches the system language, keep the system-localized names (best quality). When they differ, fall back to language-neutral names: keyboard layouts derive from the input-source ID (e.g. `com.apple.keylayout.Russian` → "Russian"), apps derive from the bundle's on-disk name (e.g. `Terminal.app` → "Terminal"). Applies to: menu status header layout name, General-tab manual-pair popups, exceptions list app names.
- **About tab centered** — title and version centered in the tab, per the user's request.
- **Operational (not code):** the user's trigger preference flips from single Shift tap to double-tap Shift (`com.ruswitcher.triggerDoubleTap = true`; the app already supports this — it's the "Double tap" switch).

## Capabilities

### New Capabilities

_None._

### Modified Capabilities

- `menu-bar-ui-and-status-icon`: the status-header requirement gains "layout name follows the app's interface language, not the system language".
- `settings-and-exception-management`: new requirements for interface-language-consistent display names (layout popups, exceptions app names) and centered About content.

## Impact

- **Code**: `LayoutSwitcher.swift` (display-name helper), `Localization.swift` (expose effective language), `AppDelegate.swift` (header name), `SettingsWindowController.swift` (popups, About tab), `ExceptionsPane.swift` (app display names).
- **No impact**: detection/conversion, settings keys, signing.

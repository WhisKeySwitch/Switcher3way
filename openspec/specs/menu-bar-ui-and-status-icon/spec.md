# Menu Bar UI and Status Icon

## Purpose

Provides the app's primary control surface: a menu-bar status item whose icon mirrors the currently active keyboard layout, and a menu exposing feature toggles, permission status, settings, and quit. This is how users see and control the app, which has no Dock presence.

## Requirements

### Requirement: Display active layout as status icon
The system SHALL display an emoji flag in the menu bar representing the currently active keyboard layout, resolved from the layout's language code rather than from substrings of its identifier.

#### Scenario: Layout with a known language code
- **WHEN** the active layout's language code maps to a flag
- **THEN** that flag is shown as the status-bar icon

### Requirement: Track system-initiated layout changes
The status icon SHALL update when the active input source changes for any reason, including switches initiated outside the app, by observing the system input-source-changed notification and additionally refreshing on a periodic safety timer.

#### Scenario: User switches layout via the system shortcut
- **WHEN** the active input source changes through the macOS layout switcher
- **THEN** the status icon updates to the new layout's flag

### Requirement: Provide feature toggles in the status menu
The status menu SHALL expose toggles for automatic layout switching, automatic conversion, key sound, and caret flag, each reflecting its current persisted state. The remote-desktop toggle SHALL only appear when its beta flag is enabled.

#### Scenario: Toggling a feature from the menu
- **WHEN** the user clicks a feature toggle in the status menu
- **THEN** the setting is persisted and the menu item's checked state reflects the new value

#### Scenario: Remote-desktop beta hidden
- **WHEN** the remote-desktop beta flag is not enabled
- **THEN** the remote-desktop toggle does not appear in the menu

### Requirement: Rebuild menu on state changes
The system SHALL rebuild the status menu when the interface language changes or when menu-relevant state changes, so that labels and check states remain accurate.

#### Scenario: Interface language changed
- **WHEN** the interface language changes
- **THEN** the menu is rebuilt with localized labels

### Requirement: Show version and app identity in the menu
The status menu SHALL display the app's version (with a development tag when present). Update-check, support, and repository links SHALL NOT appear in the menu.

#### Scenario: Menu opened
- **WHEN** the user opens the status menu
- **THEN** the current version string is visible and no update/support items are present

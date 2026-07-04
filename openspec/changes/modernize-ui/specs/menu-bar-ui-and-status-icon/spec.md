# Delta: Menu Bar UI and Status Icon (modernize-ui)

## MODIFIED Requirements

### Requirement: Provide feature toggles in the status menu
The status menu SHALL expose a "Quick toggles" group containing automatic conversion (labeled "Auto-fix as I type"), key sound, and caret flag, each reflecting its current persisted state and labeled without beta suffixes (beta badges remain only in Settings). The remote-desktop toggle SHALL only appear when its beta flag is enabled.

#### Scenario: Toggling a feature from the menu
- **WHEN** the user clicks a feature toggle in the status menu
- **THEN** the setting is persisted and the menu item's checked state reflects the new value

#### Scenario: Remote-desktop beta hidden
- **WHEN** the remote-desktop beta flag is not enabled
- **THEN** the remote-desktop toggle does not appear in the menu

#### Scenario: No beta labels in the menu
- **WHEN** the user opens the status menu
- **THEN** no toggle label contains a "(beta)" suffix

### Requirement: Show version and app identity in the menu
The status menu SHALL display the app's version (with a development tag when present) inside the status header row rather than as a separate disabled top item. Update-check, support, and repository links SHALL NOT appear in the menu.

#### Scenario: Menu opened
- **WHEN** the user opens the status menu
- **THEN** the current version string is visible within the status header and no update/support items are present

## ADDED Requirements

### Requirement: Status-first menu header
The status menu SHALL open with a header row showing the currently active layout (short badge plus localized layout name), a one-line reminder of the manual trigger, and the app version.

#### Scenario: Header reflects the active layout
- **WHEN** the user opens the menu while the U.S. layout is active
- **THEN** the header SHALL show the U.S. layout's badge and name, the trigger reminder, and the version

### Requirement: Pause with durations
The menu SHALL replace the "Enable Switcher3way" checkbox with a "Pause Switcher3way" submenu offering 30 minutes, 1 hour, and until-restart durations. While paused, the status icon SHALL visibly indicate the paused state, and the menu item SHALL become "Resume". Timed pauses SHALL re-enable the app automatically when the duration elapses.

#### Scenario: Timed pause elapses
- **WHEN** the user pauses for 30 minutes and the interval passes
- **THEN** the app SHALL resume monitoring automatically and the status icon SHALL return to the active-layout indicator

#### Scenario: Paused state is visible
- **WHEN** the app is paused
- **THEN** the status icon SHALL differ from the normal layout flag so a disabled switcher never looks enabled

#### Scenario: Manual resume
- **WHEN** the user selects Resume while paused
- **THEN** monitoring SHALL restart immediately regardless of remaining pause time

### Requirement: Conditional permissions menu item
The "Check Permissions…" item SHALL appear in the menu only when a required permission is missing; when shown, it SHALL open the onboarding checklist window.

#### Scenario: Permissions healthy
- **WHEN** both required permissions are granted
- **THEN** the menu SHALL NOT contain a permissions item

#### Scenario: Permissions broken
- **WHEN** a required permission is missing
- **THEN** the menu SHALL contain the permissions item and selecting it SHALL open the onboarding window

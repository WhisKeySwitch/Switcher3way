## ADDED Requirements

### Requirement: Check-for-updates menu item
The status menu SHALL include a localized "Check for Updates…" item in the utility group that triggers a user-initiated update check. While a check or an update installation is in progress the item SHALL be disabled and indicate the in-progress state.

#### Scenario: User checks for updates from the menu
- **WHEN** the user selects "Check for Updates…" from the status menu
- **THEN** the system SHALL run an interactive update check and report the result (update prompt, up to date, or error)

#### Scenario: Item disabled while busy
- **WHEN** an update check or installation is already running
- **THEN** the menu item SHALL be disabled and reflect that work is in progress

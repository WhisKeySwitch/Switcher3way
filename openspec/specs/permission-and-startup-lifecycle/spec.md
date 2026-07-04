# Permission and Startup Lifecycle

## Purpose

The system SHALL manage app startup, permission checks, and monitoring state so that keyboard monitoring can operate only when the required macOS permissions are available.

## Requirements

### Requirement: Check permissions during startup
The system SHALL verify Accessibility and Input Monitoring permissions when the app launches and SHALL guide the user through granting them via a single persistent onboarding checklist window instead of sequential modal alerts.

#### Scenario: Start monitoring when permissions are granted
- **WHEN** the app launches and both required permissions are already available
- **THEN** the system SHALL start keyboard monitoring and continue normal operation without showing the onboarding window

#### Scenario: Prompt for missing permissions
- **WHEN** the app launches and one or more required permissions are missing
- **THEN** the system SHALL present the onboarding checklist window before enabling monitoring

### Requirement: Synchronize login item state
The system SHALL keep the app’s login-item registration consistent with the user’s launch-at-login preference.

#### Scenario: Register login item when enabled
- **WHEN** the user enables launch-at-login
- **THEN** the system SHALL register the app as a login item

#### Scenario: Unregister login item when disabled
- **WHEN** the user disables launch-at-login
- **THEN** the system SHALL remove the app from the login-item registration

### Requirement: Rebuild the UI after lifecycle changes
The system SHALL refresh the menu and status UI when settings or permission state change so that the user sees the current state.

#### Scenario: Refresh the app menu after settings changes
- **WHEN** the user changes a setting that affects the menu or status indicators
- **THEN** the system SHALL rebuild the menu and update the visible state

### Requirement: Onboarding checklist window
The onboarding window SHALL list each required permission (Accessibility, Input Monitoring) as a checklist row with a one-line explanation of why it is needed, a live status ("Granted" or an "Open Settings" action), and an inline launch-at-login switch, replacing the separate launch-at-login alert. Grant status SHALL be detected live by polling while the window is open, without requiring the user to click anything after granting.

#### Scenario: Live grant detection
- **WHEN** the onboarding window is open and the user grants a permission in System Settings
- **THEN** the corresponding row SHALL change to "Granted" automatically within a few seconds

#### Scenario: Input Monitoring restart notice
- **WHEN** the Input Monitoring row is pending
- **THEN** its explanation SHALL state that the app restarts itself after the permission is granted, and the existing automatic relaunch behavior SHALL be preserved

#### Scenario: Closing loses nothing
- **WHEN** the user closes the onboarding window with permissions still missing
- **THEN** the app SHALL continue running in its limited state and the window SHALL be reopenable (e.g. from the menu's permissions item) with current status shown

#### Scenario: All permissions granted
- **WHEN** the last missing permission becomes granted while the window is open
- **THEN** the window SHALL reflect completion and monitoring SHALL start without additional modal alerts

# Permission and Startup Lifecycle

## Purpose

The system SHALL manage app startup, permission checks, and monitoring state so that keyboard monitoring can operate only when the required macOS permissions are available.

## Requirements

### Requirement: Check permissions during startup
The system SHALL verify Accessibility and Input Monitoring permissions when the app launches and SHALL guide the user through the required prompts when access is missing.

#### Scenario: Start monitoring when permissions are granted
- **WHEN** the app launches and both required permissions are already available
- **THEN** the system SHALL start keyboard monitoring and continue normal operation

#### Scenario: Prompt for missing permissions
- **WHEN** the app launches and one or more required permissions are missing
- **THEN** the system SHALL present the appropriate permission flow before enabling monitoring

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

## MODIFIED Requirements

### Requirement: Check permissions during startup
The system SHALL verify Accessibility and Input Monitoring permissions when the app launches and SHALL guide the user through granting them via a single persistent onboarding checklist window instead of sequential modal alerts.

These permissions are continuing preconditions, not a one-time gate. The system SHALL NOT treat a successful check at launch as evidence that monitoring still works later.

#### Scenario: Start monitoring when permissions are granted
- **WHEN** the app launches and both required permissions are already available
- **THEN** the system SHALL start keyboard monitoring and continue normal operation without showing the onboarding window

#### Scenario: Prompt for missing permissions
- **WHEN** the app launches and one or more required permissions are missing
- **THEN** the system SHALL present the onboarding checklist window before enabling monitoring

### Requirement: Onboarding checklist window
The system SHALL present a single persistent checklist window covering both permissions, with a live-updating status for each, replacing the chained modal alerts.

#### Scenario: Live grant detection
- **WHEN** the user grants a permission while the checklist is open
- **THEN** the checklist SHALL reflect the new state within a few seconds without the user returning to the app

#### Scenario: Input Monitoring restart notice
- **WHEN** Input Monitoring is granted
- **THEN** the app SHALL restart itself, because macOS requires it before the grant takes effect

#### Scenario: Closing loses nothing
- **WHEN** the user closes the onboarding window with permissions still missing
- **THEN** the app SHALL continue running in its limited state, SHALL continue watching for the missing permissions to be granted, and the window SHALL be reopenable with current status shown
- **AND** a permission granted after the window is closed SHALL start monitoring without the user relaunching the app

#### Scenario: All permissions granted
- **WHEN** both permissions are granted
- **THEN** the checklist SHALL show a completed state and monitoring SHALL be running

## ADDED Requirements

### Requirement: Detect that monitoring has stopped working

While monitoring is supposed to be active, the system SHALL periodically confirm that it actually is — that the required permissions are still held and that the event tap is still enabled. A check performed only at launch SHALL NOT be treated as evidence of the current state.

macOS revokes these grants on its own — a changed code signature is enough — and users toggle them off. Both happened during development of this app.

#### Scenario: A permission is revoked while the app runs

- **WHEN** Accessibility or Input Monitoring is withdrawn while the app is running
- **THEN** the system SHALL detect it within a short, bounded time rather than continuing to believe it is working

#### Scenario: The event tap is disabled by the system

- **WHEN** the event tap is disabled while the permissions are still held
- **THEN** the system SHALL re-enable it and continue, without involving the user

#### Scenario: The check costs nothing noticeable

- **WHEN** the app runs normally for a long period
- **THEN** the periodic check SHALL NOT cause perceptible CPU use, and SHALL NOT itself be capable of interrupting or delaying a conversion

### Requirement: Never present the app as working when it is not

When monitoring has stopped working, the system SHALL make that visible without the user having to discover it by typing. The status item SHALL show a state distinct from both running and paused, and the menu SHALL say what is wrong and what would fix it.

This app's successful state is invisible: when it is working, nothing appears on screen. So an app that has silently stopped is indistinguishable from an app with nothing to do, and the user's reasonable conclusion — that it is broken — is one the app could have corrected.

#### Scenario: Permissions lost

- **WHEN** a required permission has been revoked
- **THEN** the status item SHALL indicate the app is not working, and the menu SHALL name the missing permission and offer the way to restore it

#### Scenario: Distinguishable from pause

- **WHEN** the app is not working because a permission was revoked
- **THEN** its indication SHALL be distinguishable from the paused and disabled states, which are deliberate user choices rather than faults

#### Scenario: Recorded for a field report

- **WHEN** monitoring stops working for any reason
- **THEN** the reason SHALL be written to the diagnostic log, so that a user reporting "it stopped working" can be answered from evidence

### Requirement: Recover without a relaunch where recovery is possible

Where the app can resume by itself it SHALL do so silently. Where it cannot — a permission genuinely withdrawn — it SHALL return to the same state it uses when permissions were never granted, including watching for them to come back, so that re-granting resumes normal operation without a relaunch.

#### Scenario: Permission restored after revocation

- **WHEN** a revoked permission is granted again while the app is running
- **THEN** monitoring SHALL resume without the user relaunching the app, and the status item SHALL return to its normal state

#### Scenario: Recovery is not silently assumed

- **WHEN** the app attempts to resume monitoring and fails
- **THEN** it SHALL remain in the not-working state and SHALL NOT report itself as recovered

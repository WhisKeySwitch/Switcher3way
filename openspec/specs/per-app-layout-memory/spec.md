# Per-App Layout Memory

## Purpose

The system SHALL remember the active keyboard layout per application and SHALL restore that layout when the user returns to the same application.

## Requirements

### Requirement: Track layout state by application
The system SHALL associate the most recently used layout with the active application so that layout choices can be restored later.

#### Scenario: Record the active layout for the focused app
- **WHEN** the user changes the keyboard layout while an application is focused
- **THEN** the system SHALL store that layout association for that application

#### Scenario: Restore the remembered layout on return
- **WHEN** the user switches focus back to an application with a remembered layout
- **THEN** the system SHALL restore the previously associated layout

### Requirement: Respect feature enablement
The system SHALL only apply per-app layout memory when the feature is enabled in settings.

#### Scenario: Disable per-app memory when the feature is off
- **WHEN** the per-app layout memory feature is disabled
- **THEN** the system SHALL not restore or store application-specific layout state

### Requirement: Avoid interfering with remote desktop workflows
The system SHALL not apply the per-app layout restoration logic in contexts that should defer to a remote-desktop client.

#### Scenario: Skip restoration for remote-desktop clients
- **WHEN** the focused application is a remote-desktop client and remote-desktop mode is active
- **THEN** the system SHALL leave layout handling to the remote-desktop workflow

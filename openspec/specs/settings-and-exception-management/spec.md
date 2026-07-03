# Settings and Exception Management

## Purpose

The system SHALL expose and persist user preferences for trigger behavior, auto-conversion, layout pair selection, and the exception lists that govern when conversion is allowed or forced.

## Requirements

### Requirement: Persist user preferences
The system SHALL store settings in the app’s persistent defaults so that preferences survive app restarts and relaunches.

#### Scenario: Save a changed trigger setting
- **WHEN** the user changes the conversion trigger or related options
- **THEN** the system SHALL persist the new value in the application defaults

#### Scenario: Save a changed auto-conversion toggle
- **WHEN** the user enables or disables automatic conversion or related features
- **THEN** the system SHALL persist the new toggle state for future sessions

### Requirement: Manage exception lists
The system SHALL maintain separate lists for denied applications, denied words, and always-convert words so that conversion behavior can be tailored per context.

#### Scenario: Add a denied application
- **WHEN** the user adds an application to the denied-app list
- **THEN** the system SHALL ensure automatic conversion is skipped in that application

#### Scenario: Add an exception word
- **WHEN** the user adds a word to the denied-word or always-convert list
- **THEN** the system SHALL use that exception during later conversion decisions

### Requirement: Keep protected defaults intact
The system SHALL preserve the protected password-manager applications that are always treated as denied for automatic conversion.

#### Scenario: Preserve protected application entries
- **WHEN** the user updates the denied-app list
- **THEN** the system SHALL keep the protected password-manager entries in effect

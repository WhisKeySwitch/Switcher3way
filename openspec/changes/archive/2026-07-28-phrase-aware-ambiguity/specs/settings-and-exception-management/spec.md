# Settings and Exception Management — Delta

## ADDED Requirements

### Requirement: Ambiguous-word language preference
The system SHALL provide a persisted setting for the language used to convert wrong-layout words that are valid in more than one language, with the values Ukrainian, Russian, and "do not convert". The default SHALL be Ukrainian. The setting SHALL be presented on the Auto-fix tab of the Settings window as a labeled popup and take effect without an app restart.

#### Scenario: Default value on first run
- **WHEN** the app runs without a stored ambiguous-language preference
- **THEN** the effective preference SHALL be Ukrainian

#### Scenario: Changing the preference takes effect immediately
- **WHEN** the user selects a different value in the Auto-fix tab popup
- **THEN** the next ambiguous-word evaluation SHALL use the new value without restarting the app

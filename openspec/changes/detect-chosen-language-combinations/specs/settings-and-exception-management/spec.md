# Spec Delta

## MODIFIED Requirements

### Requirement: Ambiguous-word language preference
The system SHALL provide a persisted setting for the language used to convert wrong-layout words that are valid in more than one language. Its values SHALL be each supported detection language the user currently has enabled, other than English, plus "do not convert". The default SHALL be Ukrainian. A stored value whose language is not currently enabled SHALL be kept rather than reset, and SHALL simply settle no ties until that language is enabled again. The setting SHALL be presented on the Auto-fix tab of the Settings window as a labeled popup and take effect without an app restart.

#### Scenario: Default value on first run
- **WHEN** the app runs without a stored ambiguous-language preference
- **THEN** the effective preference SHALL be Ukrainian

#### Scenario: Changing the preference takes effect immediately
- **WHEN** the user selects a different value in the Auto-fix tab popup
- **THEN** the next ambiguous-word evaluation SHALL use the new value without restarting the app

#### Scenario: The popup follows the enabled languages
- **WHEN** the user has English, German and French enabled and opens the Auto-fix tab
- **THEN** the popup SHALL offer German, French and "do not convert", each named in its own language

#### Scenario: A stored preference survives a disabled layout
- **WHEN** the stored preference is Ukrainian and the user disables the Ukrainian layout, then enables it again later
- **THEN** the preference SHALL still be Ukrainian, and while Ukrainian was disabled the popup SHALL show it as the current value marked unavailable

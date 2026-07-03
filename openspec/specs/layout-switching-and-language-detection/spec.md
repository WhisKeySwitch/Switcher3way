# Layout Switching and Language Detection

## Purpose

The system SHALL switch the active keyboard layout to the resolved target layout based on the current input and the installed input sources, including support for multi-layout detection beyond the original two-layout model.

## Requirements

### Requirement: Discover installed layouts and their languages
The system SHALL enumerate the installed keyboard input sources and determine their language codes so that conversion decisions can be made against the available layouts.

#### Scenario: Resolve available layouts at runtime
- **WHEN** the application needs to convert or switch layouts
- **THEN** the system SHALL inspect the currently installed input sources and their language metadata

#### Scenario: Handle layouts without a known language
- **WHEN** an installed layout does not expose a usable language code
- **THEN** the system SHALL ignore that layout for language-based detection

### Requirement: Resolve a target layout for conversion
The system SHALL select a target layout when the typed input appears to be valid in a different language and the detection logic finds a single unambiguous candidate.

#### Scenario: Switch to a single winning layout
- **WHEN** the typed input is valid in exactly one alternative language and passes the safety gates
- **THEN** the system SHALL switch to the corresponding target layout and retype the word in that layout

#### Scenario: Leave the input unchanged when the result is ambiguous
- **WHEN** multiple alternative layouts could plausibly match the input
- **THEN** the system SHALL avoid switching layouts and SHALL leave the current text unchanged

### Requirement: Support direct manual layout switching
The system SHALL allow the user to switch directly to a specific layout or to the opposite layout from the configured pair.

#### Scenario: Switch to an explicit layout
- **WHEN** the user requests a specific layout through the app’s switching logic
- **THEN** the system SHALL select that input source through the macOS input-source API

#### Scenario: Switch to the opposite configured layout
- **WHEN** the user requests the opposite layout from the current one
- **THEN** the system SHALL select the alternate layout from the configured pair

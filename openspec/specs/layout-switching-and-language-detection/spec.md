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
The system SHALL allow the user to switch directly to a specific layout, to cycle through an ordered list of candidate layouts, and to restore a previously recorded layout. Manual switching SHALL NOT depend on a fixed two-layout pair.

#### Scenario: Switch to an explicit layout
- **WHEN** the user requests a specific layout through the app’s switching logic
- **THEN** the system SHALL select that input source through the macOS input-source API

#### Scenario: Cycle to the next candidate layout
- **WHEN** the user advances the manual trigger through the candidate layouts
- **THEN** the system SHALL select the next candidate input source in the ordered cycle, wrapping back to the pre-conversion layout after the last candidate

#### Scenario: Restore the recorded previous layout
- **WHEN** the app needs to undo a conversion
- **THEN** the system SHALL re-select the exact layout that was recorded as active before the conversion, rather than selecting the alternate of a configured pair

#### Scenario: Fallback switching where per-layout rendering is unavailable
- **WHEN** keystrokes arrive pre-rendered as characters (e.g. through a remote-desktop client) so candidate rendering across layouts is not possible
- **THEN** the system SHALL advance the local layout to the next installed input source as a deterministic fallback

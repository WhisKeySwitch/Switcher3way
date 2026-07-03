# Manual Conversion and Undo

## Purpose

The system SHALL convert typed text between keyboard layouts when the user invokes the configured trigger, and SHALL support a second invocation to reverse the most recent conversion.

## Requirements

### Requirement: Convert the last typed word
The system SHALL convert the most recently typed word or the currently selected text when the manual trigger is invoked in an editable context.

#### Scenario: Convert the last word through the buffer-based retype path
- **WHEN** the user types a word and invokes the manual trigger
- **THEN** the system SHALL retype the word using the converted text and preserve any trailing spaces that followed the word

#### Scenario: Convert selected text when no word buffer is available
- **WHEN** the user has selected text and invokes the manual trigger
- **THEN** the system SHALL convert the selected text in place using the clipboard-based fallback path when needed

### Requirement: Support undo of the previous conversion
The system SHALL reverse the most recent conversion when the manual trigger is invoked again within the supported conversion state.

#### Scenario: Reverse the last buffer-based conversion
- **WHEN** the user invokes the manual trigger again after a successful conversion
- **THEN** the system SHALL restore the original text that was replaced by the last conversion

#### Scenario: Skip undo when no prior conversion state exists
- **WHEN** there is no prior conversion state to reverse
- **THEN** the system SHALL not perform a conversion and SHALL leave the current text unchanged

### Requirement: Preserve conversion context across repeated actions
The system SHALL track the last conversion outcome so that subsequent trigger actions can operate on the correct text span.

#### Scenario: Track the most recent conversion result
- **WHEN** a conversion succeeds
- **THEN** the system SHALL store the original and converted text together with the relevant text span for later undo

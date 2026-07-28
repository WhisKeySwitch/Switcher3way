# Automatic Conversion on Word Boundaries — Delta

## ADDED Requirements

### Requirement: Abort conversion when the user keeps typing
The system SHALL abort an in-flight automatic conversion as soon as a real (user-originated, non-synthetic) keystroke is detected after the conversion was scheduled. Synthetic events emitted by the retype engine itself SHALL NOT count as user input. An aborted conversion SHALL restore any characters it already erased, so the on-screen text is never left partially deleted, and SHALL be treated as not having happened: no exception-list, undo-cycle, or conversion bookkeeping may record it.

#### Scenario: User types during the injection window
- **WHEN** an automatic conversion has been scheduled and the user presses a key before the replacement text has been fully injected
- **THEN** the system SHALL stop injecting further backspaces or text, restore any already-erased characters, and leave the user's new keystrokes untouched

#### Scenario: No concurrent typing
- **WHEN** an automatic conversion runs to completion without any real keystroke arriving during injection
- **THEN** the system SHALL replace the word exactly as before this change

### Requirement: Switch layout only after successful replacement
The system SHALL change the active keyboard layout as a consequence of an automatic conversion only after the text replacement has completed successfully. If the conversion is aborted or fails, the layout SHALL remain the one the user was typing in.

#### Scenario: Layout unchanged on aborted conversion
- **WHEN** an automatic conversion is aborted because the user kept typing
- **THEN** the active keyboard layout SHALL remain unchanged, so subsequent keystrokes keep rendering in the layout the user is typing in

#### Scenario: Layout switches after completed conversion
- **WHEN** an automatic conversion completes its text replacement
- **THEN** the system SHALL switch to the target layout and update the status icon

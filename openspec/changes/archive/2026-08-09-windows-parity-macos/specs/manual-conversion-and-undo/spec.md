## ADDED Requirements

### Requirement: Refuse manual conversion in a password field
The manual trigger SHALL be subject to the same password-field gate as automatic conversion. Although
the trigger is an explicit user action — which is why it otherwise acts on words automatic detection
would decline — it SHALL NOT read, retype, or cycle text while the focused control is detected as a
password field or while secure input is active. The refusal SHALL be recorded in the log and SHALL
leave the active layout unchanged.

#### Scenario: Trigger invoked in a password field
- **WHEN** the user invokes the manual trigger while the focused control is reported as a password field
- **THEN** the system SHALL perform no text replacement, SHALL start no candidate cycle, SHALL leave the active layout unchanged, and SHALL record the suppression in the log

#### Scenario: Trigger invoked with a selection inside a password field
- **WHEN** the user invokes the manual trigger with text selected in a control reported as a password field
- **THEN** the system SHALL NOT read the selection through the clipboard fallback and SHALL leave the text and the clipboard untouched

### Requirement: Offer to remember a word when a conversion is undone
When a manual trigger invocation restores the original text of a recently applied conversion, the
system SHALL treat that as the user rejecting the conversion and SHALL raise the remember-this-word
offer for the form that had been on screen. The offer SHALL be non-blocking and SHALL NOT interrupt
typing.

#### Scenario: User undoes a conversion just applied
- **WHEN** the candidate cycle restores the original text of a conversion applied within the offer window, with no typing in between
- **THEN** the system SHALL raise the remember-this-word offer naming the converted form that was on screen

#### Scenario: Cycle passes through intermediate candidates
- **WHEN** repeated trigger invocations move between candidate layouts without restoring the original text
- **THEN** the system SHALL NOT raise the remember-this-word offer

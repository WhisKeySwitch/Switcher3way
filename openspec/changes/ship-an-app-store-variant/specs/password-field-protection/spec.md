## MODIFIED Requirements

### Requirement: Detect a focused password field beyond the secure-input flag
The system SHALL determine whether the currently focused control is a password field using every signal
its build variant can actually read. A field SHALL be treated as a password field when any of the
following holds:

1. the focused element's Accessibility subrole is the secure-text-field subrole;
2. the focused element is a text-entry role whose title, description, placeholder value, or
   help text contains password wording;
3. the process-global secure-input flag is set;
4. the frontmost application is one for which conversion is always suppressed, such as a password
   manager.

Signals 1 and 2 require inspecting the focused Accessibility element of another application. That
inspection is unavailable in a sandboxed build, where those signals SHALL be reported as
**unavailable** rather than as negative results. Signals 3 and 4 SHALL be available in every variant.

Any single positive signal SHALL be sufficient. The check SHALL deliberately over-block: a false
positive costs one unconverted word in a field labelled as a password, whereas a false negative
rewrites a credential.

#### Scenario: Masked password field in a browser
- **WHEN** the focused element is a masked password input in a browser or Electron application
- **THEN** the system SHALL report the focused control as a password field

#### Scenario: Masked password field in a browser, sandboxed variant
- **WHEN** the focused element is a masked password input in a browser, in a build that cannot inspect Accessibility elements
- **THEN** the system SHALL still report the focused control as a password field, because browsers enable the process-global secure-input flag for password inputs

#### Scenario: Password field revealed by a show/hide toggle
- **WHEN** the focused element is a text input that is not masked but whose accessible name, placeholder, or description contains password wording (for example "Password Hide password")
- **THEN** the system SHALL report the focused control as a password field, even though no masking and no secure-input flag is present

#### Scenario: A signal that cannot be read is not a negative answer
- **WHEN** a variant cannot inspect the focused Accessibility element
- **THEN** the element-based signals SHALL be reported as unavailable, and the verdict SHALL rest on the signals that variant can read

#### Scenario: Ordinary text field
- **WHEN** the focused element is a plain text field with no password wording and no masking
- **THEN** the system SHALL report the focused control as not a password field

### Requirement: Report which signal produced the verdict
The system SHALL expose a diagnostic description naming each signal's individual result and the
focused element, so that a guard which never fires is distinguishable from a guard which correctly
finds nothing. The description SHALL distinguish three states per signal — positive, negative, and
unavailable in this build variant — because a signal that cannot run and a signal that ran and found
nothing are different facts with the same consequence. This description SHALL be available both in the
debug log and through a command-line diagnostic mode of the application binary.

#### Scenario: Diagnosing the guard from the log
- **WHEN** a user reports that conversion happened in a password field
- **THEN** the log SHALL show each signal's individual result for that decision, including which signals were unavailable

#### Scenario: Diagnosing the guard interactively
- **WHEN** the user runs the application binary in its password-diagnostic mode
- **THEN** the system SHALL print the same per-signal breakdown for whatever control currently has focus

#### Scenario: Diagnosing a sandboxed build
- **WHEN** the diagnostic mode is run in the App Store variant
- **THEN** it SHALL report the element-based signals as unavailable rather than printing them as negative

## ADDED Requirements

### Requirement: A variant that cannot inspect elements compensates at application granularity
When element-level inspection is unavailable, the system SHALL fall back to application-level
suppression: conversion SHALL be suppressed entirely while the frontmost application is one known to
handle credentials, and the user SHALL be able to add applications to that list.

This SHALL NOT be presented to the user as equivalent protection. The variant's documentation SHALL
state plainly that password detection in that build rests on the secure-input flag and the application
list, and that a credential typed into a field which sets neither may be converted.

#### Scenario: Password manager in the foreground
- **WHEN** the frontmost application is a password manager and element inspection is unavailable
- **THEN** the system SHALL suppress automatic conversion, manual conversion and conversion feedback for that application

#### Scenario: The limitation is disclosed
- **WHEN** a variant ships without element-level password detection
- **THEN** its user-facing documentation SHALL state which protection it does and does not provide, rather than describing the guard as though both variants behaved identically

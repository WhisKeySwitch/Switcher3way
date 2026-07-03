# Automatic Conversion on Word Boundaries

## Purpose

The system SHALL automatically detect likely incorrect-layout words at word boundaries and SHALL perform a conversion only when the input passes the configured safety gates.

## Requirements

### Requirement: Evaluate words at word boundaries
The system SHALL inspect the current word when a word boundary is detected and evaluate it for possible automatic conversion.

#### Scenario: Trigger evaluation after a space or boundary event
- **WHEN** the user finishes a word and a boundary event occurs
- **THEN** the system SHALL evaluate the preceding word for automatic conversion

#### Scenario: Skip evaluation when auto-conversion is disabled
- **WHEN** automatic conversion is turned off in settings
- **THEN** the system SHALL not initiate an automatic conversion on a word boundary

### Requirement: Apply safety gates before converting
The system SHALL reject automatic conversion for words that are too short, contain punctuation or digits, look like acronyms or code identifiers, or are otherwise excluded by policy.

#### Scenario: Reject short or code-like input
- **WHEN** the typed input is short, all caps, mixed-script, or otherwise matches the soft-gate exclusions
- **THEN** the system SHALL leave the text unchanged

#### Scenario: Respect user exception lists
- **WHEN** the application, the typed word, or the converted word matches a configured exception rule
- **THEN** the system SHALL prevent automatic conversion for that input

### Requirement: Defer in remote or secure contexts
The system SHALL avoid automatic conversion when the active context is a secure input field, a protected password manager, or a remote-desktop client that should defer to the remote host.

#### Scenario: Avoid conversion in secure input
- **WHEN** the active input context is secure or protected
- **THEN** the system SHALL not perform automatic conversion

#### Scenario: Defer in remote desktop mode
- **WHEN** the app is running in remote-desktop mode and the frontmost client is a remote-desktop application
- **THEN** the system SHALL not perform automatic conversion on the local instance

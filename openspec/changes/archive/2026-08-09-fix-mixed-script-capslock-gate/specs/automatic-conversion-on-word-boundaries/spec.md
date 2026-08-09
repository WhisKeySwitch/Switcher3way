## MODIFIED Requirements

### Requirement: Apply safety gates before converting
The system SHALL reject automatic conversion for words whose letter core is a single letter, looks like an acronym or code identifier, or is otherwise excluded by policy. The safety gates SHALL be evaluated against the word's letter core — the input with leading and trailing non-letter characters removed — so that attached punctuation does not by itself prevent conversion.

The case-dependent vetoes SHALL be distinguished from the case-independent one. The all-caps veto and the internal-capital (camelCase) veto SHALL be skipped while Caps Lock is active, because under Caps Lock every letter is uppercase and neither signal carries information. The mixed-script veto — Latin and Cyrillic letters in the same token — SHALL be applied regardless of Caps Lock, because a token drawn from two alphabets is a code identifier whatever the shift state was.

#### Scenario: Reject single-letter or code-like input
- **WHEN** the typed input's letter core is a single letter, all caps, mixed-script, or otherwise matches the soft-gate exclusions
- **THEN** the system SHALL leave the text unchanged

#### Scenario: Mixed-script token with Caps Lock active
- **WHEN** the input's letter core contains both Latin and Cyrillic letters and Caps Lock is active
- **THEN** the system SHALL reject it, exactly as it does when Caps Lock is off

#### Scenario: All-caps and camelCase remain exempt under Caps Lock
- **WHEN** the input's letter core is entirely uppercase, or carries an internal capital, and Caps Lock is active
- **THEN** the system SHALL NOT reject it on either of those grounds, since Caps Lock makes both signals meaningless

#### Scenario: Convert a word that has attached punctuation
- **WHEN** the typed word carries leading or trailing punctuation (for example a trailing "!" or a wrapping parenthesis) and its letter core is a valid word in exactly one alternative language
- **THEN** the system SHALL convert the word, validating only the letter core while re-rendering the whole token — punctuation included — in the target layout

#### Scenario: Accept short words of at least two letters
- **WHEN** the typed input's letter core is two or more letters and it otherwise passes the gates
- **THEN** the system SHALL allow the word to be evaluated for conversion

#### Scenario: Respect user exception lists
- **WHEN** the application, the typed word, or the converted word matches a configured exception rule
- **THEN** the system SHALL prevent automatic conversion for that input

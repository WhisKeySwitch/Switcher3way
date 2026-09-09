## MODIFIED Requirements

### Requirement: Apply safety gates before converting
The system SHALL reject automatic conversion for words whose letter core is a single letter, looks like an acronym or code identifier, or is otherwise excluded by policy. The safety gates SHALL be evaluated against the word's letter core — the input with leading and trailing non-letter characters removed — so that attached punctuation does not by itself prevent conversion.

An apostrophe or hyphen *inside* the letter core SHALL NOT by itself fail the gates: contractions and hyphenated words (`you're`, `it's`, `кто-то`, `будь-ласка`) are ordinary words of the languages the app serves, and the same words already pass when typed in their own layout. Any other non-letter inside the core — a digit, a slash, an underscore — SHALL still be treated as code and rejected.

The case-dependent vetoes SHALL be distinguished from the case-independent one. The all-caps veto and the internal-capital (camelCase) veto SHALL be skipped while Caps Lock is active, because under Caps Lock every letter is uppercase and neither signal carries information. The mixed-script veto — Latin and Cyrillic letters in the same token — SHALL be applied regardless of Caps Lock, because a token drawn from two alphabets is a code identifier whatever the shift state was.

#### Scenario: Reject single-letter or code-like input
- **WHEN** the typed input's letter core is a single letter, all caps, mixed-script, or otherwise matches the soft-gate exclusions
- **THEN** the system SHALL leave the text unchanged

#### Scenario: A contraction or hyphenated word passes the gates
- **WHEN** the typed input renders in an alternative language as a word whose letter core contains an internal apostrophe or hyphen and is valid there (for example `You're` typed on a Cyrillic layout, or `Кто-то` typed on the Latin one)
- **THEN** the system SHALL evaluate it for conversion exactly as it would a plain word, and SHALL convert it when it is valid in exactly one alternative language

#### Scenario: Other internal punctuation is still code
- **WHEN** the typed input's letter core contains an internal digit, slash, dot, or underscore
- **THEN** the system SHALL reject it as a code identifier and leave the text unchanged

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

### Requirement: Resolve ambiguous words by preferred language
The system SHALL convert a word that is not valid in the current (typed) language but valid in more than one other installed language to the *preferred ambiguity language* configured in settings, instead of leaving it unchanged. When the setting is "do not convert", the system SHALL keep today's behavior and leave ambiguous words untouched. When the current phrase is already locked to a language (see phrase correction below) **and that language is one of the word's candidates**, the locked language SHALL take precedence over the setting (unless the setting is "do not convert"). When the phrase is locked to a language that is *not* among the candidates — the phrase reads as English and the word is valid in Ukrainian and Russian — the lock says nothing about which candidate is right, and the system SHALL fall back to the configured preference.

#### Scenario: Ambiguous word converts to the preferred language
- **WHEN** the user types a word in the wrong layout whose letter core is valid in both Ukrainian and Russian (e.g. «добре») and the preferred ambiguity language is Ukrainian
- **THEN** the system SHALL convert the word using the Ukrainian layout and switch to it, marking the word internally as a defaulted conversion

#### Scenario: Preference set to "do not convert"
- **WHEN** the preferred ambiguity language setting is "do not convert" and an ambiguous word is typed in the wrong layout
- **THEN** the system SHALL leave the word unchanged (previous behavior)

#### Scenario: Phrase lock overrides the preference
- **WHEN** the current phrase already contains a word valid in exactly one language (e.g. a ru-only word) and a new ambiguous word is typed in the wrong layout
- **THEN** the system SHALL convert the ambiguous word to the phrase's locked language, even if the preference names another language

#### Scenario: A lock outside the candidates yields to the preference
- **WHEN** the current phrase is locked to a language that is not one of the ambiguous word's candidate languages (e.g. locked to English, word valid in Ukrainian and Russian) and the preference is a language
- **THEN** the system SHALL convert the word to the preferred language, mark it as a defaulted conversion, and record in the log that the preference was used because the lock was not a candidate

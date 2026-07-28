# Automatic Conversion on Word Boundaries — Delta

## ADDED Requirements

### Requirement: Resolve ambiguous words by preferred language
The system SHALL convert a word that is not valid in the current (typed) language but valid in more than one other installed language to the *preferred ambiguity language* configured in settings, instead of leaving it unchanged. When the setting is "do not convert", the system SHALL keep today's behavior and leave ambiguous words untouched. When the current phrase is already locked to a language (see phrase correction below), that locked language SHALL take precedence over the setting (unless the setting is "do not convert").

#### Scenario: Ambiguous word converts to the preferred language
- **WHEN** the user types a word in the wrong layout whose letter core is valid in both Ukrainian and Russian (e.g. «добре») and the preferred ambiguity language is Ukrainian
- **THEN** the system SHALL convert the word using the Ukrainian layout and switch to it, marking the word internally as a defaulted conversion

#### Scenario: Preference set to "do not convert"
- **WHEN** the preferred ambiguity language setting is "do not convert" and an ambiguous word is typed in the wrong layout
- **THEN** the system SHALL leave the word unchanged (previous behavior)

#### Scenario: Phrase lock overrides the preference
- **WHEN** the current phrase already contains a word valid in exactly one language (e.g. a ru-only word) and a new ambiguous word is typed in the wrong layout
- **THEN** the system SHALL convert the ambiguous word to the phrase's locked language, even if the preference names another language

### Requirement: Correct defaulted words when the phrase language is disambiguated
The system SHALL track the words typed since the last hard reset (Enter, Tab, arrows, mouse click, app or focus switch — the same events that reset the word buffer) as the current phrase. When a word valid in exactly one language arrives and the phrase contains words previously converted by the ambiguity default to a *different* language, the system SHALL re-convert those defaulted words to the newly established language in a single text replacement together with the current word, and switch the layout to it. If the phrase also contains a word locked to a conflicting language, the system SHALL NOT re-convert anything (contradictory phrase — precision-first). Words that were not defaulted (valid in the typed language, kept, or already locked) SHALL keep their on-screen text during the correction.

#### Scenario: Russian-only word re-converts earlier defaulted words
- **WHEN** the phrase contains words defaulted to Ukrainian (e.g. «добре») and the user then types a word valid only in Russian in the wrong layout
- **THEN** the system SHALL replace the segment from the first defaulted word through the current word so the defaulted words and the current word are rendered in the Russian layout, and SHALL switch to that layout

#### Scenario: Contradictory phrase is left untouched
- **WHEN** the phrase contains a word valid only in Ukrainian and the user then types a word valid only in Russian
- **THEN** the system SHALL convert only the current word per the standard single-word rule and SHALL NOT re-convert any earlier words

#### Scenario: Phrase memory resets on hard boundaries
- **WHEN** the user presses Enter/Tab/an arrow key, clicks the mouse, or switches apps or focus
- **THEN** the system SHALL start a new empty phrase, and words typed before the reset SHALL never be re-converted

#### Scenario: Phrase correction is undoable
- **WHEN** a phrase correction has replaced a segment and the user activates the manual trigger with no input in between
- **THEN** the system SHALL restore the segment's previous on-screen text and the pre-correction layout, following the standard conversion-undo cycle

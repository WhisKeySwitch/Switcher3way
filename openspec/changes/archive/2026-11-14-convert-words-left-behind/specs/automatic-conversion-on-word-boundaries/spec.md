## MODIFIED Requirements

### Requirement: Correct defaulted words when the phrase language is disambiguated
The system SHALL track the words typed since the last hard reset (Enter, Tab, arrows, mouse click, app or focus switch — the same events that reset the word buffer) as the current phrase. When a word valid in exactly one language arrives and the phrase contains words previously converted by the ambiguity default to a *different* language, the system SHALL re-convert those defaulted words to the newly established language in a single text replacement together with the current word, and switch the layout to it. If the phrase also contains a word locked to a conflicting language, the system SHALL NOT re-convert anything (contradictory phrase — precision-first). Words valid in the language they were typed in, and words already locked, SHALL keep their on-screen text during the correction. A word that was left alone because it is not a word in the language it was typed in — including a single letter, which is never judged alone — SHALL be converted with the segment when the correction already spans it, and SHALL NOT by itself start a correction.

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

#### Scenario: A word nobody recognised is not left behind inside a correction
- **WHEN** the user, on the English layout, types the keys of `Це все, чим я допомогти`, the words before `чим` are held, `чим` was left alone as not a word anywhere, `я` was left alone as a single letter, and `допомогти` then converts to Ukrainian with a phrase correction
- **THEN** the corrected segment SHALL read `Це все, чим я допомогти` in the Ukrainian layout, with no Latin word left between the converted ones

#### Scenario: A word nobody recognised does not start a correction
- **WHEN** the phrase's only earlier word is one left alone as not a word anywhere (an English typo such as `Exchanfe`), with no held or defaulted word before it, and the next word converts to Ukrainian
- **THEN** the system SHALL convert only the current word and SHALL leave the earlier unrecognised word as typed

#### Scenario: A word valid where it was typed stays as typed
- **WHEN** a correction spans a word that was left alone because it is valid in the language it was typed in
- **THEN** the system SHALL reproduce that word's on-screen text unchanged

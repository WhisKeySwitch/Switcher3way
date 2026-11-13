## ADDED Requirements

### Requirement: Recognise the short words a language's speakers type
Below four letters a dictionary hit SHALL count only when the word is a known short word of that language, because the dictionaries also accept noise at that length. Every word under four letters that the language's dictionary accepts SHALL be reviewed and recorded as a typed word or as noise. A word recorded as a typed word SHALL count as a word of its language.

#### Scenario: A common Ukrainian pronoun is a Ukrainian word
- **WHEN** the user types `він`, `чим`, `от`, `же` or `йти` on the Ukrainian layout
- **THEN** the system SHALL treat it as a Ukrainian word and leave it unchanged

#### Scenario: A common Ukrainian word typed on the English layout is recognised
- **WHEN** the user types the keys of `він` (`dsy`) on the English layout, inside a phrase that has settled as Ukrainian
- **THEN** the system SHALL treat it as the Ukrainian word `він`, not as a string that is a word in no language

#### Scenario: Dictionary noise is still not believed
- **WHEN** a string under four letters is accepted by a dictionary but was recorded as noise in the review, such as `wt` in English
- **THEN** the system SHALL NOT treat it as a word of that language

#### Scenario: A gap in the list fails the review
- **WHEN** a dictionary-accepted short string of a reviewed language is neither on the language's list nor recorded as noise
- **THEN** the test suite SHALL fail and name the string

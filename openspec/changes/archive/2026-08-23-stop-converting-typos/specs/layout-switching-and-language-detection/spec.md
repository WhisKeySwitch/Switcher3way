## MODIFIED Requirements

### Requirement: Resolve a target layout for conversion
The system SHALL select a target layout when the typed input appears to be valid in a different language and the detection logic finds a single unambiguous candidate.

A word being valid in another language SHALL NOT by itself be sufficient grounds to convert it. Before converting, the system SHALL weigh that evidence against the likelier ordinary explanation — that the user is writing the language they are already in and mistyped a key — and SHALL decline to convert when it cannot tell the two apart. Precision here is not a preference: a false conversion moves the keyboard layout as well as the text, so every one of them costs the user the rest of the sentence, whereas a missed conversion costs one trigger press.

#### Scenario: Switch to a single winning layout
- **WHEN** the typed input is valid in exactly one alternative language and passes the safety gates
- **THEN** the system SHALL switch to the corresponding target layout and retype the word in that layout

#### Scenario: Leave a probable typo alone
- **WHEN** the typed input is long enough to be judged on its own, and the language currently being typed in contains a real word within one edit of it — a dropped letter, a doubled or wrong letter, or two letters swapped
- **THEN** the system SHALL treat the input as a mistyping of that language and SHALL leave both the text and the layout unchanged
- **AND** this SHALL hold whether the candidate language uses a different script (a Ukrainian typo reading as English) or the same one (a Ukrainian typo reading as Russian)

#### Scenario: Decline to judge a word too short to carry evidence
- **WHEN** the typed input is shorter than the length at which a dictionary hit is meaningful
- **THEN** the system SHALL NOT decide it on the dictionary alone, because a large fraction of very short strings appear in any dictionary as abbreviations and initialisms, and because the one-edit test above degenerates at that length into matching everything
- **AND** the system SHALL instead resolve it from the language the surrounding phrase has already settled into

#### Scenario: A settled phrase outweighs a short word that contradicts it
- **WHEN** a short word reads as a language other than the one the surrounding phrase has settled into
- **THEN** the system SHALL leave the word unchanged

#### Scenario: Hold a short word when nothing has settled the phrase
- **WHEN** a word is too short to judge and no surrounding word has established the phrase's language
- **THEN** the system SHALL leave the text and layout unchanged, and SHALL report the word as held rather than as decided
- **AND** the caller SHALL retain its keystrokes so that a later word which does settle the phrase converts the held word along with itself
- **AND** a run of consecutive held words that all read as the same single language SHALL be taken as settling the phrase to that language, so that a message in which no word is long enough to decide anything is still converted

#### Scenario: Report why a word was left alone
- **WHEN** the system decides to leave a word unchanged
- **THEN** it SHALL report which rule reached that decision — that the word is already valid where it was typed, that it is not a word in any installed language, that it reads as another language but the language being typed holds a word one keystroke away, or that it is too short and the phrase disagrees
- **AND** the reason SHALL be recorded in the debug log, because leaving a word alone changes nothing on screen and is otherwise indistinguishable from the detection never having run at all
- **AND** where the reason is that the word is already valid in the language it was typed in, the caller SHALL take this as establishing the phrase's language, it being the strongest such evidence available

#### Scenario: An explicit request is not second-guessed
- **WHEN** the user asks for a conversion through the manual trigger
- **THEN** the system SHALL apply neither the one-edit test nor the short-word rule, and SHALL offer the candidate layouts as it would for any word, however short

#### Scenario: Re-render the whole token in the target layout
- **WHEN** the system converts a word whose keystrokes include punctuation keys
- **THEN** the system SHALL render every keystroke — letters and punctuation alike — through the target layout, so that punctuation keys that differ between layouts (for example the key that types "/" on a Latin layout and "." on the Cyrillic PC layouts) produce the target layout's character rather than the source character

#### Scenario: Leave the input unchanged when the result is ambiguous
- **WHEN** multiple alternative layouts could plausibly match the input
- **THEN** the system SHALL avoid switching layouts and SHALL leave the current text unchanged

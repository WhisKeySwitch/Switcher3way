# Layout Switching and Language Detection

## Purpose

The system SHALL switch the active keyboard layout to the resolved target layout based on the current input and the installed input sources, including support for multi-layout detection beyond the original two-layout model.

## Requirements

### Requirement: Discover installed layouts and their languages
The system SHALL enumerate the installed keyboard input sources and determine their language codes so that conversion decisions can be made against the available layouts.

#### Scenario: Resolve available layouts at runtime
- **WHEN** the application needs to convert or switch layouts
- **THEN** the system SHALL inspect the currently installed input sources and their language metadata

#### Scenario: Handle layouts without a known language
- **WHEN** an installed layout does not expose a usable language code
- **THEN** the system SHALL ignore that layout for language-based detection

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

### Requirement: Support direct manual layout switching
The system SHALL allow the user to switch directly to a specific layout, to cycle through an ordered list of candidate layouts, and to restore a previously recorded layout. Manual switching SHALL NOT depend on a fixed two-layout pair.

#### Scenario: Switch to an explicit layout
- **WHEN** the user requests a specific layout through the app’s switching logic
- **THEN** the system SHALL select that input source through the macOS input-source API

#### Scenario: Cycle to the next candidate layout
- **WHEN** the user advances the manual trigger through the candidate layouts
- **THEN** the system SHALL select the next candidate input source in the ordered cycle, wrapping back to the pre-conversion layout after the last candidate

#### Scenario: Restore the recorded previous layout
- **WHEN** the app needs to undo a conversion
- **THEN** the system SHALL re-select the exact layout that was recorded as active before the conversion, rather than selecting the alternate of a configured pair

#### Scenario: Fallback switching where per-layout rendering is unavailable
- **WHEN** keystrokes arrive pre-rendered as characters (e.g. through a remote-desktop client) so candidate rendering across layouts is not possible
- **THEN** the system SHALL advance the local layout to the next installed input source as a deterministic fallback

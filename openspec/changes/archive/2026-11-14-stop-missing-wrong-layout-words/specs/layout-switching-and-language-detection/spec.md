## MODIFIED Requirements

### Requirement: Resolve a target layout for conversion
The system SHALL select a target layout when the typed input appears to be valid in a different language and the detection logic finds a single unambiguous candidate.

A word being valid in another language SHALL NOT by itself be sufficient grounds to convert it. Before converting, the system SHALL weigh that evidence against the likelier ordinary explanation — that the user is writing the language they are already in and mistyped a key — and SHALL decline to convert when it cannot tell the two apart. Precision here is not a preference: a false conversion moves the keyboard layout as well as the text, so every one of them costs the user the rest of the sentence, whereas a missed conversion costs one trigger press.

The guards SHALL be applied only where they were measured to discriminate. A guard consulted outside its measured band does not add precision; it silently spends recall, and the loss is invisible because leaving a word alone moves nothing on screen.

A token whose letter core is empty — digits, punctuation, or symbols only — SHALL NOT be treated as a valid word in any language.

Below the length at which a dictionary hit is meaningful, a dictionary verdict SHALL NOT stand on its own: the word SHALL also be one that the language's speakers actually type, judged against a curated list of that language's short words. This applies to the language being typed in as well as to the candidates, because a hit on the typed side is what keeps a word — and a piece of dictionary noise keeping a word is indistinguishable, on screen, from the app not running. A language for which no such list exists SHALL fall through to the dictionary alone, so that an unlisted language behaves as it did before rather than having every short word vetoed.

#### Scenario: Switch to a single winning layout
- **WHEN** the typed input is valid in exactly one alternative language and passes the safety gates
- **THEN** the system SHALL switch to the corresponding target layout and retype the word in that layout

#### Scenario: Leave a probable typo alone
- **WHEN** the typed input is at least six letters long, its winning rendering differs from the text on screen, and the language currently being typed in contains a real word within one edit of it — a dropped letter, a doubled or wrong letter, or two letters swapped
- **THEN** the system SHALL treat the input as a mistyping of that language and SHALL leave both the text and the layout unchanged
- **AND** this SHALL hold whether the candidate language uses a different script (a Ukrainian typo reading as English) or the same one (a Ukrainian typo that reads as a different Russian word)

#### Scenario: A four- or five-letter word is not second-guessed by the one-edit test
- **WHEN** the typed input's letter core is four or five letters, it is valid in exactly one alternative language, and no surrounding word has settled the phrase to a different language
- **THEN** the system SHALL convert it on the dictionary hit without consulting the one-edit test, because at that length nearly every string has a real word one edit away and the test no longer separates typos from wrong-layout words

#### Scenario: The same text in a sibling language switches only the layout, and only with the phrase's word for it
- **WHEN** the typed input is not a word in the language being typed, is a word in exactly one other language, that language's rendering of the keystrokes is letter-for-letter the text already on screen (a Russian word typed on the Ukrainian layout, or the reverse), and the surrounding phrase has already settled into that other language
- **THEN** the system SHALL NOT apply the one-edit test, because a fumbled key and a wrong keyboard leave the same text and the test would be choosing between layouts, not texts
- **AND** the system SHALL switch to the winning language's layout without erasing or retyping anything, SHALL record the word as locked to that language, and SHALL report the decision as a layout-only switch

#### Scenario: The same text without the phrase's corroboration keeps the layout
- **WHEN** the typed input is spelled identically in a sibling language and the phrase has not settled into that language, whatever the word's length
- **THEN** the system SHALL leave the layout unchanged, because a typo in the language being typed is a real word of the sibling language as often as not (адже mistyped as даже), and moving the layout on it is the failure the one-edit test exists to prevent
- **AND** it SHALL report this as its own reason — the layout was deliberately left, not a typo seen

#### Scenario: Decline to judge a word too short to carry evidence
- **WHEN** the typed input — judged by the shorter of its own letter core and the winning rendering's letter core, since punctuation keys are letters on the other layout and a two-letter hit means nothing whichever side it is on — is shorter than the length at which a dictionary hit is meaningful
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

#### Scenario: A lone held word with no vowel settles on its own
- **WHEN** a held word reads as exactly one language, and its rendering in the language being typed contains no vowel of that language, and the vowel-less abbreviation fixture measures zero false conversions for this rule
- **THEN** the system SHALL convert the held word to that language at once, without waiting for a second held word, and SHALL report the decision with this reason
- **AND** a held word whose typed rendering does contain a vowel, or that reads as more than one language, SHALL continue to wait for the phrase as before

#### Scenario: Dictionary noise does not keep a short word
- **WHEN** the typed input is under the meaningful length, the dictionary of the language being typed in reports it as a word, but it is not among that language's curated short words (for example the English dictionary accepting "wt", which is what a Ukrainian "це" becomes when typed on a Latin layout)
- **THEN** the system SHALL NOT treat the word as valid in the language being typed, and SHALL go on to consider the other languages' readings
- **AND** where the surrounding phrase already reads as the language of the winning reading, the word SHALL be converted

#### Scenario: A genuinely typed short word is still kept
- **WHEN** the typed input is under the meaningful length and is among the curated short words of the language being typed in
- **THEN** the system SHALL keep it, even when the phrase has settled into another language, because converting a word the user meant costs more than missing one they did not

#### Scenario: A token without letters is not a word
- **WHEN** the typed input's letter core is empty — a number, a time, a smiley, or punctuation alone
- **THEN** the system SHALL report it as not a word in any installed language, SHALL NOT convert it, and it SHALL NOT settle the phrase's language

#### Scenario: Report why a word was left alone
- **WHEN** the system decides to leave a word unchanged
- **THEN** it SHALL report which rule reached that decision — that the word is already valid where it was typed, that it is not a word in any installed language, that it reads as another language but the language being typed holds a word one keystroke away, that it is too short and the phrase disagrees, or that it is spelled the same in a sibling language and the phrase does not corroborate a layout switch
- **AND** the reason SHALL be recorded in the debug log, because leaving a word alone changes nothing on screen and is otherwise indistinguishable from the detection never having run at all
- **AND** where the reason is that the word is already valid in the language it was typed in and its letter core is at least four letters, the caller SHALL take this as establishing the phrase's language, it being the strongest such evidence available
- **AND** where the word is valid in the language it was typed in but shorter than four letters, the caller SHALL leave the phrase's language as it was, because at that length the dictionary accepts abbreviations and single letters that say nothing about what language the phrase is in

#### Scenario: An explicit request is not second-guessed
- **WHEN** the user asks for a conversion through the manual trigger
- **THEN** the system SHALL apply neither the one-edit test nor the short-word rule, and SHALL offer the candidate layouts as it would for any word, however short

#### Scenario: Re-render the whole token in the target layout
- **WHEN** the system converts a word whose keystrokes include punctuation keys
- **THEN** the system SHALL render every keystroke — letters and punctuation alike — through the target layout, so that punctuation keys that differ between layouts (for example the key that types "/" on a Latin layout and "." on the Cyrillic PC layouts) produce the target layout's character rather than the source character

#### Scenario: Leave the input unchanged when the result is ambiguous
- **WHEN** multiple alternative layouts could plausibly match the input
- **THEN** the system SHALL avoid switching layouts and SHALL leave the current text unchanged

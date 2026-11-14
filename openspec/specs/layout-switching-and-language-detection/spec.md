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

### Requirement: One dictionary verdict per word per decision
Within a single conversion decision, the system SHALL ask the dictionary about a given rendering at most once and SHALL act on that verdict throughout the decision. The recorded diagnostic dump and the decision outcome SHALL therefore never contradict each other about a word's validity.

#### Scenario: A flip-flopping dictionary cannot split one decision
- **WHEN** the dictionary would answer differently on a repeated query for the same word during one decision
- **THEN** the decision SHALL be based on the single verdict actually taken, and the diagnostic record SHALL reflect that same verdict

### Requirement: Quarantine a dictionary that fails its canaries
The system SHALL periodically verify each language's dictionary against two canaries — a common word of the language that must validate, and a keyboard-mash string that must not. When a probe fails, the system SHALL treat that language's dictionary as unavailable for conversion decisions until a later probe passes, SHALL log the quarantine and the recovery unconditionally, and SHALL prefer doing nothing over acting on a dictionary known to be answering incorrectly.

#### Scenario: An accept-everything episode is caught
- **WHEN** a language's dictionary validates the keyboard-mash canary
- **THEN** the language SHALL be excluded from detection (no conversions into or out of it on dictionary evidence) until a subsequent probe passes, and the episode SHALL be visible in the log

#### Scenario: A reject-everything episode is caught
- **WHEN** a language's dictionary rejects the common-word canary
- **THEN** the language SHALL be excluded from detection until a subsequent probe passes, rather than silently eating conversions word by word

#### Scenario: A quarantined language stays a candidate
- **WHEN** a language's dictionary is quarantined and the typed keys render as a plausible word shape in that language
- **THEN** the language SHALL remain in the candidate set with its verdict marked unusable, a sibling language SHALL NOT win the word by default (the word is left alone and the reason recorded) unless the phrase has already settled on the sibling, and the gibberish rescue SHALL weigh the quarantined rendering by shape as it does any other — so a Ukrainian word typed on the English layout during a uk quarantine is never converted into a Russian misspelling of itself

#### Scenario: Typing in a quarantined language
- **WHEN** the current layout's language is quarantined
- **THEN** the word SHALL be left alone and the record SHALL name the quarantine, not a missing language

#### Scenario: A healthy dictionary is untouched
- **WHEN** the probes pass
- **THEN** validation behaves exactly as before, and the probe cost stays off the per-keystroke path (probes run on first use and on a cooldown interval, not per word)

### Requirement: Confirm the dictionary before acting on it
Before converting on dictionary evidence, the system SHALL confirm that the language's dictionary is answering correctly at that moment, and SHALL decline the conversion when it is not. A periodic health check alone SHALL NOT be treated as sufficient, because the interval between checks is a window in which a newly-incorrect dictionary would convert a name into keyboard mash and move the layout with it.

#### Scenario: An episode that began after the last check is caught
- **WHEN** a language's dictionary passed its canaries earlier but has since begun answering incorrectly, and a word's only winner is that language
- **THEN** the system SHALL re-check that dictionary before acting, SHALL leave the text and layout unchanged, and SHALL record that the dictionary failed its self-check

#### Scenario: The confirmation stays off the per-word path
- **WHEN** many words are evaluated and none results in a conversion
- **THEN** the confirmation SHALL not be performed per word, and repeated confirmations within a short freshness window SHALL reuse the verdict already taken

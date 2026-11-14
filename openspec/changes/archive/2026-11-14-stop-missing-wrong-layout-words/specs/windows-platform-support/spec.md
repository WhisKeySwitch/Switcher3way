## MODIFIED Requirements

### Requirement: Preserve N-way precision-first detection semantics
The Windows build SHALL reproduce the application's N-way detection behavior: validate the word's
letter core, convert when the input is valid in exactly one alternative language, re-render the whole
token (including punctuation keys) in the target layout, and apply the same short-word and code-like
safety gates. When the input is valid in **more than one** alternative language (uk↔ru ambiguity),
the Windows build SHALL resolve it to the *preferred ambiguity language* — the phrase's locked
language if the current phrase is locked to one of the candidates, otherwise the configured preference
— rather than leaving it unchanged, unless the preference is "do not convert". Input already valid in
the current language SHALL be left unchanged. The Windows build SHALL track the words typed since the
last hard reset as a phrase and, when a later word is valid in exactly one language, re-convert earlier
words that were defaulted to a *different* language in a single replacement together with that word; a
phrase locked to a conflicting language SHALL NOT be re-converted (precision-first).

The Windows build SHALL apply the same evidence rules as the macOS core, with the same thresholds:
the one-edit typo test is consulted only from six letters up, on the shorter of the typed and winning
letter cores; a same-text winner switches the layout without rewriting only when the phrase already
reads as its language, and is otherwise kept with its own reason; a token with no letters is not a word
anywhere; a word valid in the current language settles the phrase only from four
letters; an internal apostrophe or hyphen passes the soft gates; a lone held word with no vowel in the
typed language settles at once once the fixture measurement admits the rule. The two ports SHALL
decide identically for the same input, and the shared measurement suite SHALL show typo conversion
still at zero after these changes.

#### Scenario: Switch to a single unambiguous winner
- **WHEN** the buffered word's letter core is valid in exactly one alternative language and passes the safety gates
- **THEN** the system SHALL switch to that language's layout and rewrite the word in it

#### Scenario: Resolve an ambiguous word to the preferred language
- **WHEN** the word's letter core is valid in more than one language, the preference is a language (not "do not convert"), and no phrase lock among the candidates overrides it
- **THEN** the system SHALL convert the word to the preferred language's layout and mark it internally as a defaulted conversion

#### Scenario: Preference "do not convert" leaves ambiguous input unchanged
- **WHEN** the word is ambiguous and the ambiguity preference is "do not convert"
- **THEN** the system SHALL leave the text and layout unchanged

#### Scenario: Phrase self-corrects when disambiguated later
- **WHEN** the phrase contains words defaulted to one language and the user then types a word valid only in another language in the wrong layout, with no conflicting lock
- **THEN** the system SHALL replace the segment from the first defaulted word through the current word so all of them render in the newly established language, and SHALL switch to that layout

#### Scenario: Contradictory phrase is left untouched
- **WHEN** the phrase already contains a word valid only in one language and the user then types a word valid only in a conflicting language
- **THEN** the system SHALL convert only the current word per the single-word rule and SHALL NOT re-convert earlier words

#### Scenario: Convert words with attached punctuation
- **WHEN** a convertible word carries leading or trailing punctuation
- **THEN** the system SHALL validate only the letter core and rewrite the whole token — punctuation included — in the target layout

#### Scenario: The same decision on both ports
- **WHEN** the shared test inputs for the typo-guard band, the same-text winner, the empty letter core, the short current-language word, the internal apostrophe, and the vowel-less held word are evaluated by the Windows core
- **THEN** each SHALL produce the outcome the macOS core's tests assert for the same input

#### Scenario: Typo conversion stays at zero
- **WHEN** the paragraph-level typing simulation is re-run after these rules are applied
- **THEN** the measured typo-conversion rate SHALL remain 0% and wrong-layout recall SHALL not fall

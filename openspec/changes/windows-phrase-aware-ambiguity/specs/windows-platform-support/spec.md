# Windows Platform Support — Delta

## MODIFIED Requirements

### Requirement: Preserve N-way precision-first detection semantics
The Windows build SHALL reproduce the application's N-way detection behavior: validate the word's
letter core, convert when the input is valid in exactly one alternative language, re-render the whole
token (including punctuation keys) in the target layout, and apply the same short-word and code-like
safety gates. When the input is valid in **more than one** alternative language (uk↔ru ambiguity),
the Windows build SHALL resolve it to the *preferred ambiguity language* — the phrase's locked
language if the current phrase is locked, otherwise the configured preference — rather than leaving
it unchanged, unless the preference is "do not convert". Input already valid in the current language
SHALL be left unchanged. The Windows build SHALL track the words typed since the last hard reset as a
phrase and, when a later word is valid in exactly one language, re-convert earlier words that were
defaulted to a *different* language in a single replacement together with that word; a phrase locked
to a conflicting language SHALL NOT be re-converted (precision-first).

#### Scenario: Switch to a single unambiguous winner
- **WHEN** the buffered word's letter core is valid in exactly one alternative language and passes the safety gates
- **THEN** the system SHALL switch to that language's layout and rewrite the word in it

#### Scenario: Resolve an ambiguous word to the preferred language
- **WHEN** the word's letter core is valid in more than one language, the preference is a language (not "do not convert"), and no phrase lock overrides it
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

### Requirement: Rewrite typed text in place
The Windows build SHALL replace the mistyped word with its converted form by erasing the original
characters and inserting the corrected Unicode text, with a clipboard-based fallback for selected
text. When a real (user-originated, non-synthetic) keystroke is detected while a replacement is in
progress, the Windows build SHALL abort the replacement, restore any characters it has already
erased, and record no conversion — so that neither a single-word rewrite nor a multi-word phrase
correction can leave the on-screen text partially deleted.

#### Scenario: Rewrite a buffered word
- **WHEN** a conversion is applied to a buffered word
- **THEN** the system SHALL erase the original characters and insert the converted text, preserving any trailing spaces

#### Scenario: Abort and restore on concurrent typing
- **WHEN** the user types a real key while a single-word or multi-word segment replacement is being injected
- **THEN** the system SHALL stop injecting, restore the characters it already erased, leave the layout unchanged, and treat the conversion as not having happened

#### Scenario: Surface protected targets rather than failing silently
- **WHEN** the foreground window cannot receive synthesized input because it runs at a higher integrity level
- **THEN** the system SHALL NOT report a successful conversion and SHALL make the limitation observable

### Requirement: Provide manual conversion and undo
The Windows build SHALL let the user convert the last word or selection on demand via a configurable
trigger, cycle through candidate layouts on repeated invocations, and restore the original text and
pre-conversion layout when the cycle completes. When the word is ambiguous, the first candidate
offered SHALL be the preferred ambiguity language (when it is one of the candidates), so a single
trigger invocation yields the same result automatic conversion would.

#### Scenario: Convert on explicit trigger
- **WHEN** the user invokes the manual trigger after typing a word
- **THEN** the system SHALL convert the word to the best candidate layout even if automatic detection would have left it unchanged

#### Scenario: Ambiguous word offers the preferred language first
- **WHEN** the user invokes the manual trigger on a word valid in more than one language and the preference names one of them
- **THEN** the first candidate applied SHALL be the preferred ambiguity language

#### Scenario: Cycle and restore
- **WHEN** the user repeatedly invokes the trigger with no typing in between
- **THEN** the system SHALL advance through the remaining candidate layouts and, after the last one, restore the original text and the layout active before the first conversion

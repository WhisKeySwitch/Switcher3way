# Windows Platform Support

## Purpose

The system SHALL, on Windows, reproduce Switcher3way's N-way wrong-layout detection and correction behavior across English, Ukrainian, and Russian — observing keystrokes, rendering them through every installed layout, validating against bundled offline dictionaries, and switching/rewriting only on a single unambiguous winner — while adapting to Windows-specific input, layout, and distribution mechanisms. This capability is a target contract for a future Windows build; it is not yet implemented in code.
## Requirements
### Requirement: Observe keystrokes and buffer words globally
The Windows build SHALL observe keystrokes system-wide without requiring focus in the app, and SHALL buffer the current word and detect word boundaries so that finished words can be evaluated, mirroring the macOS keystroke buffer.

#### Scenario: Buffer a word up to a boundary
- **WHEN** the user types letters followed by a space or other word-boundary key in any foreground application
- **THEN** the system SHALL record the ordered keystrokes of the completed word and mark that a boundary occurred

#### Scenario: Reset the buffer on unsafe cursor movement
- **WHEN** the user moves the caret with arrows, clicks the mouse, or switches applications
- **THEN** the system SHALL discard the current keystroke buffer so a later rewrite cannot delete unrelated text

### Requirement: Enumerate installed layouts and their languages
The Windows build SHALL enumerate the installed keyboard layouts and determine each layout's language so that conversion decisions can be made against the available layouts.

#### Scenario: Resolve available layouts at runtime
- **WHEN** the system needs to evaluate or switch layouts
- **THEN** the system SHALL inspect the currently installed keyboard layouts and their language identifiers

#### Scenario: Ignore layouts without a usable language
- **WHEN** an installed layout does not map to a language usable for validation
- **THEN** the system SHALL exclude that layout from language-based detection

### Requirement: Render buffered keystrokes through each candidate layout
The Windows build SHALL render the buffered keystrokes into text as each candidate layout would produce it, so the input can be validated in every layout's language.

#### Scenario: Produce per-layout renderings
- **WHEN** the system evaluates a completed word against the installed layouts
- **THEN** the system SHALL produce, for each candidate layout, the character string those keystrokes would yield in that layout

#### Scenario: Preserve dead-key and live-typing state
- **WHEN** the system renders keystrokes through a layout that uses dead keys
- **THEN** the rendering SHALL NOT corrupt the user's in-progress keyboard state or subsequent keystrokes

### Requirement: Validate words offline against bundled dictionaries
The Windows build SHALL validate candidate words against dictionaries bundled with the application, without a network connection and without depending on optional operating-system language features.

#### Scenario: Validate without installed OS language packs
- **WHEN** the target language's operating-system spellcheck feature is not installed
- **THEN** the system SHALL still validate words for that language using the bundled dictionaries

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

### Requirement: Switch the foreground application's layout
The Windows build SHALL change the active keyboard layout of the foreground application,
accounting for the per-thread nature of the Windows input language, and SHALL confirm the
change took effect rather than assuming a single switch mechanism always succeeds.

#### Scenario: Change the layout of the active window
- **WHEN** the system decides to convert a word to another language
- **THEN** the system SHALL activate the corresponding layout for the foreground application so continued typing uses that layout

#### Scenario: Confirm the switch and fall back when it does not take effect
- **WHEN** the system requests a foreground-layout change through its primary mechanism
- **THEN** the system SHALL determine whether the active layout actually changed, and SHALL attempt an alternative switch mechanism when the primary request did not take effect

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
trigger invocation yields the same result automatic conversion would. The same trigger SHALL also
cancel an automatic conversion: an auto-fix seeds a single-candidate cycle whose candidate is
already on screen, so the first trigger invocation after it restores the original text and layout.

#### Scenario: Convert on explicit trigger
- **WHEN** the user invokes the manual trigger after typing a word
- **THEN** the system SHALL convert the word to the best candidate layout even if automatic detection would have left it unchanged

#### Scenario: Ambiguous word offers the preferred language first
- **WHEN** the user invokes the manual trigger on a word valid in more than one language and the preference names one of them
- **THEN** the first candidate applied SHALL be the preferred ambiguity language

#### Scenario: Cycle and restore
- **WHEN** the user repeatedly invokes the trigger with no typing in between
- **THEN** the system SHALL advance through the remaining candidate layouts and, after the last one, restore the original text and the layout active before the first conversion

#### Scenario: Cancel an automatic conversion with the trigger
- **WHEN** the user invokes the trigger immediately after an automatic conversion, with no typing in between
- **THEN** the system SHALL restore the original text and the layout that was active before the automatic conversion

### Requirement: Apply exclusion and exception policy
The Windows build SHALL suppress automatic conversion in excluded applications and secure input contexts, and SHALL honor user-configured never-convert and always-convert word lists.

#### Scenario: Skip an excluded application
- **WHEN** the foreground application matches the denied-apps list or is a credential/password context
- **THEN** the system SHALL not perform automatic conversion in that context

#### Scenario: Honor word exception lists
- **WHEN** the typed or converted word matches a configured never-convert or always-convert rule
- **THEN** the system SHALL respectively prevent or force the conversion for that word

### Requirement: Present a tray-based status and control surface
The Windows build SHALL provide a system-tray presence that shows the current status and offers the core controls (enable/disable, auto-fix toggle, pause, and access to settings), analogous to the macOS menu-bar item.

#### Scenario: Show status and toggles in the tray
- **WHEN** the user opens the tray icon's menu
- **THEN** the system SHALL display the current enabled/paused state and provide controls to toggle conversion, pause it, and open settings

### Requirement: Distribute as a signed, offline application
The Windows build SHALL be distributed as a code-signed installer and SHALL operate entirely offline at runtime.

#### Scenario: Signed distribution
- **WHEN** the application is packaged for release
- **THEN** the binaries SHALL be Authenticode-signed and delivered through a signed installer

#### Scenario: No runtime network dependency
- **WHEN** the application performs detection, validation, or conversion
- **THEN** it SHALL do so without any network access


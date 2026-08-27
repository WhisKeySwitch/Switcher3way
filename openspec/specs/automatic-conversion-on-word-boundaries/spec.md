# Automatic Conversion on Word Boundaries

## Purpose

The system SHALL automatically detect likely incorrect-layout words at word boundaries and SHALL perform a conversion only when the input passes the configured safety gates.
## Requirements
### Requirement: Evaluate words at word boundaries
The system SHALL inspect the current word when a word boundary is detected and evaluate it for possible automatic conversion.

#### Scenario: Trigger evaluation after a space or boundary event
- **WHEN** the user finishes a word and a boundary event occurs
- **THEN** the system SHALL evaluate the preceding word for automatic conversion

#### Scenario: Skip evaluation when auto-conversion is disabled
- **WHEN** automatic conversion is turned off in settings
- **THEN** the system SHALL not initiate an automatic conversion on a word boundary

### Requirement: Apply safety gates before converting
The system SHALL reject automatic conversion for words whose letter core is a single letter, looks like an acronym or code identifier, or is otherwise excluded by policy. The safety gates SHALL be evaluated against the word's letter core — the input with leading and trailing non-letter characters removed — so that attached punctuation does not by itself prevent conversion.

The case-dependent vetoes SHALL be distinguished from the case-independent one. The all-caps veto and the internal-capital (camelCase) veto SHALL be skipped while Caps Lock is active, because under Caps Lock every letter is uppercase and neither signal carries information. The mixed-script veto — Latin and Cyrillic letters in the same token — SHALL be applied regardless of Caps Lock, because a token drawn from two alphabets is a code identifier whatever the shift state was.

#### Scenario: Reject single-letter or code-like input
- **WHEN** the typed input's letter core is a single letter, all caps, mixed-script, or otherwise matches the soft-gate exclusions
- **THEN** the system SHALL leave the text unchanged

#### Scenario: Mixed-script token with Caps Lock active
- **WHEN** the input's letter core contains both Latin and Cyrillic letters and Caps Lock is active
- **THEN** the system SHALL reject it, exactly as it does when Caps Lock is off

#### Scenario: All-caps and camelCase remain exempt under Caps Lock
- **WHEN** the input's letter core is entirely uppercase, or carries an internal capital, and Caps Lock is active
- **THEN** the system SHALL NOT reject it on either of those grounds, since Caps Lock makes both signals meaningless

#### Scenario: Convert a word that has attached punctuation
- **WHEN** the typed word carries leading or trailing punctuation (for example a trailing "!" or a wrapping parenthesis) and its letter core is a valid word in exactly one alternative language
- **THEN** the system SHALL convert the word, validating only the letter core while re-rendering the whole token — punctuation included — in the target layout

#### Scenario: Accept short words of at least two letters
- **WHEN** the typed input's letter core is two or more letters and it otherwise passes the gates
- **THEN** the system SHALL allow the word to be evaluated for conversion

#### Scenario: Respect user exception lists
- **WHEN** the application, the typed word, or the converted word matches a configured exception rule
- **THEN** the system SHALL prevent automatic conversion for that input

### Requirement: Abort conversion when the user keeps typing
The system SHALL abort an in-flight automatic conversion as soon as a real (user-originated, non-synthetic) keystroke is detected after the conversion was scheduled. Synthetic events emitted by the retype engine itself SHALL NOT count as user input. An aborted conversion SHALL restore any characters it already erased, so the on-screen text is never left partially deleted, and SHALL be treated as not having happened: no exception-list, undo-cycle, or conversion bookkeeping may record it.

#### Scenario: User types during the injection window
- **WHEN** an automatic conversion has been scheduled and the user presses a key before the replacement text has been fully injected
- **THEN** the system SHALL stop injecting further backspaces or text, restore any already-erased characters, and leave the user's new keystrokes untouched

#### Scenario: No concurrent typing
- **WHEN** an automatic conversion runs to completion without any real keystroke arriving during injection
- **THEN** the system SHALL replace the word exactly as before this change

### Requirement: Switch layout only after successful replacement
The system SHALL change the active keyboard layout as a consequence of an automatic conversion only after the text replacement has completed successfully. If the conversion is aborted or fails, the layout SHALL remain the one the user was typing in.

#### Scenario: Layout unchanged on aborted conversion
- **WHEN** an automatic conversion is aborted because the user kept typing
- **THEN** the active keyboard layout SHALL remain unchanged, so subsequent keystrokes keep rendering in the layout the user is typing in

#### Scenario: Layout switches after completed conversion
- **WHEN** an automatic conversion completes its text replacement
- **THEN** the system SHALL switch to the target layout and update the status icon

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

### Requirement: Defer in remote or secure contexts
The system SHALL avoid automatic conversion when the active context is a secure input field, a control
detected as a password field by the focused-element password check, a protected password manager, or a
remote-desktop client that should defer to the remote host. The secure-context gate SHALL consult both
the process-global secure-input flag and the focused-element password check, because a field can be a
password field without the flag being set — an unmasked "show password" input, a web form that masks in
its own code, or a host that never requests secure event input. When conversion is suppressed for a
secure context, the phrase memory SHALL be reset, so that nothing typed into that field can influence a
later phrase correction.

#### Scenario: Avoid conversion in secure input
- **WHEN** the active input context is secure or protected
- **THEN** the system SHALL not perform automatic conversion

#### Scenario: Avoid conversion in an unmasked password field
- **WHEN** the focused control is reported as a password field by the focused-element check while the process-global secure-input flag is clear
- **THEN** the system SHALL not perform automatic conversion, SHALL reset the phrase memory, and SHALL record the suppression in the log

#### Scenario: Defer in remote desktop mode
- **WHEN** the app is running in remote-desktop mode and the frontmost client is a remote-desktop application
- **THEN** the system SHALL not perform automatic conversion on the local instance

### Requirement: Do not attempt a replacement that cannot succeed
Automatic conversion replaces the completed word together with the boundary character that ended it, which means it must be able to reproduce that boundary. Where it cannot, the system SHALL decline the conversion rather than attempt it.

Attempting it is strictly worse than declining. The replacement cannot land, so the text is unchanged either way; what the failed attempt adds is a rewrite of the user's text, a verification failure, an undo, and an interruption — at the end of every line they type.

#### Scenario: A word ended by a key whose character cannot be re-typed
- **WHEN** a word is completed by a boundary that the replacement mechanism cannot reproduce — a line break or a tab, where the injection method used for text has no effect
- **THEN** the system SHALL leave the text and layout unchanged, SHALL record why in the diagnostic log, and SHALL NOT begin a replacement
- **AND** SHALL NOT raise a failure notification, because nothing failed — the app declined

#### Scenario: Reproducing the boundary as a keystroke is not a substitute
- **WHEN** a boundary character cannot be injected as text
- **THEN** the system SHALL NOT re-issue it as a key press in order to proceed, because the same key means different things in different targets — inserting a line break in an editor, and submitting in a message box where it has already been pressed once — and the two cannot be told apart before acting

#### Scenario: Ordinary word boundaries are unaffected
- **WHEN** a word is completed by a space
- **THEN** conversion SHALL proceed exactly as before

### Requirement: Report a failed replacement in terms of what failed
Where a replacement is attempted and does not succeed, any message shown to the user SHALL describe what actually happened. A message that names a cause the system has not established — in particular attributing an ordinary failure to the target running with elevated privileges — SHALL NOT be used as a general-purpose failure notice.

#### Scenario: A replacement that did not land is reported as such
- **WHEN** a replacement is written, checked, found not to match, and the original restored
- **THEN** the user SHALL be told that the conversion did not take effect and that their text was put back, rather than being told the window may be running as administrator

#### Scenario: A genuinely privileged target is still named as one
- **WHEN** the system's input is refused outright because the target runs at a higher integrity level
- **THEN** the message SHALL say so, since in that case it is both true and actionable


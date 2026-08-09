# Manual Conversion and Undo

## Purpose

The system SHALL convert typed text between keyboard layouts when the user invokes the configured trigger, and SHALL support repeated invocations to cycle through candidate layouts and reverse the most recent conversion.
## Requirements
### Requirement: Convert the last typed word
The system SHALL convert the most recently typed word or the currently selected text when the manual trigger is invoked in an editable context. Because the trigger is an explicit user action, the system SHALL produce a conversion even when automatic detection would decline: if N-way detection finds a single unambiguous target the system SHALL convert to it, and otherwise the system SHALL convert to the first alternative candidate layout (the next installed layout whose rendering of the keystrokes differs from the current one). Candidate retention and ordering SHALL follow *Keep layouts of different languages reachable* and *Order candidates by the evidence*.

#### Scenario: Convert the last word through the buffer-based retype path
- **WHEN** the user types a word and invokes the manual trigger
- **THEN** the system SHALL retype the word using the converted text and preserve any trailing spaces that followed the word

#### Scenario: Convert selected text when no word buffer is available
- **WHEN** the user has selected text and invokes the manual trigger
- **THEN** the system SHALL convert the selected text in place using the clipboard-based fallback path when needed

#### Scenario: Act on an ambiguous word
- **WHEN** the user invokes the manual trigger on a word that automatic detection would leave unchanged (valid in the current language, or valid in more than one alternative language)
- **THEN** the system SHALL still convert the word to the first alternative candidate layout rather than leaving it unchanged, and SHALL record the candidate cycle so repeated invocations can advance through the remaining candidates

### Requirement: Support undo of the previous conversion
The system SHALL reverse or advance the most recent conversion when the manual trigger is invoked again without intervening typing. Repeated invocations SHALL cycle through the ordered candidate layouts, retyping the word in each and switching the active layout to it; completing the cycle SHALL restore the original text and the exact layout that was active immediately before the first conversion.

#### Scenario: Cycle to the next candidate layout
- **WHEN** the user invokes the manual trigger again after a conversion, with no typing in between, and more than two candidate layouts exist
- **THEN** the system SHALL retype the word in the next candidate layout and switch the active layout to it

#### Scenario: Completing the cycle restores the original state
- **WHEN** repeated trigger invocations advance past the last candidate
- **THEN** the system SHALL restore the original typed text and re-select the exact layout that was active before the first conversion

#### Scenario: Skip undo when no prior conversion state exists
- **WHEN** there is no prior conversion state to reverse
- **THEN** the system SHALL not perform a conversion and SHALL leave the current text unchanged

### Requirement: Preserve conversion context across repeated actions
The system SHALL track the last conversion outcome — the original and converted text, the relevant text span, the ordered candidate layouts with the current position in the cycle, and the layout that was active immediately before the conversion — so that subsequent trigger actions operate on the correct span and can restore the precise prior layout.

#### Scenario: Track the most recent conversion result
- **WHEN** a conversion succeeds
- **THEN** the system SHALL store the original and converted text, the text span, the candidate cycle and index, and the pre-conversion layout ID for later cycling and undo

#### Scenario: Restore the pre-conversion layout on undo
- **WHEN** a conversion (manual or automatic) is reversed via the trigger
- **THEN** the system SHALL re-select the recorded pre-conversion layout rather than inferring a layout from a fixed two-layout pair

### Requirement: Refuse manual conversion in a password field
The manual trigger SHALL be subject to the same password-field gate as automatic conversion. Although
the trigger is an explicit user action — which is why it otherwise acts on words automatic detection
would decline — it SHALL NOT read, retype, or cycle text while the focused control is detected as a
password field or while secure input is active. The refusal SHALL be recorded in the log and SHALL
leave the active layout unchanged.

#### Scenario: Trigger invoked in a password field
- **WHEN** the user invokes the manual trigger while the focused control is reported as a password field
- **THEN** the system SHALL perform no text replacement, SHALL start no candidate cycle, SHALL leave the active layout unchanged, and SHALL record the suppression in the log

#### Scenario: Trigger invoked with a selection inside a password field
- **WHEN** the user invokes the manual trigger with text selected in a control reported as a password field
- **THEN** the system SHALL NOT read the selection through the clipboard fallback and SHALL leave the text and the clipboard untouched

### Requirement: Offer to remember a word when a conversion is undone
When a manual trigger invocation restores the original text of a recently applied conversion, the
system SHALL treat that as the user rejecting the conversion and SHALL raise the remember-this-word
offer for the form that had been on screen. The offer SHALL be non-blocking and SHALL NOT interrupt
typing.

#### Scenario: User undoes a conversion just applied
- **WHEN** the candidate cycle restores the original text of a conversion applied within the offer window, with no typing in between
- **THEN** the system SHALL raise the remember-this-word offer naming the converted form that was on screen

#### Scenario: Cycle passes through intermediate candidates
- **WHEN** repeated trigger invocations move between candidate layouts without restoring the original text
- **THEN** the system SHALL NOT raise the remember-this-word offer

### Requirement: Keep layouts of different languages reachable
When two or more installed layouts render the input identically, the system SHALL keep them as
separate candidates whenever they belong to **different languages**, and SHALL collapse them into one
candidate only when they belong to the **same language**. Candidate de-duplication SHALL therefore key
on the rendered text together with the candidate's language, and the text already on screen SHALL
suppress only a candidate of the source layout's own language.

A cross-language candidate whose text matches another candidate — or matches the text already on
screen — is a step that changes the active layout without changing a visible character. The system
SHALL still offer it: Ukrainian and Russian spell every word built from their shared letters
identically, so collapsing by text alone leaves one of the two languages unreachable from the trigger
altogether.

#### Scenario: Word spelled the same in two languages
- **WHEN** the user triggers conversion of a word whose render is identical in Ukrainian and Russian
- **THEN** the system SHALL offer both as steps, so repeated triggers can reach either language

#### Scenario: Selection already showing the shared spelling
- **WHEN** the user triggers conversion on selected text that already reads as the shared spelling, with one of the two languages active
- **THEN** the system SHALL offer the sibling language as a step, even though the text it produces is identical to the selection

#### Scenario: Two layouts of the same language
- **WHEN** two installed layouts of the same language render the input identically
- **THEN** the system SHALL offer only one of them, since nothing distinguishes the second

#### Scenario: The source layout's own text is not re-offered
- **WHEN** a candidate would reproduce the text already on screen in the source layout's own language
- **THEN** the system SHALL NOT offer it

### Requirement: An automatic conversion seeds the full candidate cycle
When an automatic conversion is applied, the system SHALL record a candidate cycle containing **all**
the layouts that render the word differently — the applied one first, then the rest — so that
repeated trigger invocations walk through every installed layout before restoring the original text
and the pre-conversion layout. Seeding only the applied conversion makes every other layout
unreachable from the trigger, since no plan is built on the undo path.

A conversion that also applied a **phrase correction** SHALL keep a single step: its erased span is a
whole segment, and per-word candidates do not describe how other layouts render that segment.

#### Scenario: Cycling on after an automatic conversion
- **WHEN** Auto-fix converts a word to one of three installed layouts and the user taps the trigger repeatedly with no typing in between
- **THEN** the system SHALL show the word in each remaining layout in turn, and only then restore the original text and the pre-conversion layout

#### Scenario: Undo still reachable
- **WHEN** the user continues tapping past the last candidate
- **THEN** the system SHALL restore exactly what was typed and the layout that was active before the conversion, and SHALL raise the remember-this-word offer

#### Scenario: Phrase correction
- **WHEN** the applied conversion also re-converted earlier words of the phrase
- **THEN** the cycle SHALL contain the single corrected segment, so one further tap restores the whole segment

### Requirement: Order candidates by the evidence
The first candidate offered SHALL be the one the evidence points at, so a single trigger press gives
the same answer auto-fix would:

1. when exactly one language validates the render, that language's candidate leads;
2. when more than one validates it, the candidate of the **preferred ambiguity language** from
   settings leads, provided that language is among the validating ones;
3. otherwise the established rotation order stands.

This SHALL apply to candidates built from recorded keystrokes and to candidates built from a
selection alike.

#### Scenario: Word valid in only one of two identically-rendering languages
- **WHEN** the user triggers conversion of a word whose render is identical in Ukrainian and Russian but is a valid word only in Russian
- **THEN** the Russian candidate SHALL lead, regardless of which of the two layouts comes first in the input-source order

#### Scenario: Ambiguous word follows the preference
- **WHEN** the render is valid in both Ukrainian and Russian and the preferred ambiguity language is Russian
- **THEN** the Russian candidate SHALL lead, and the Ukrainian one SHALL remain reachable by triggering again

#### Scenario: Preference set to "do not convert"
- **WHEN** the render is valid in both languages and the ambiguity preference is "do not convert"
- **THEN** the rotation order SHALL stand, since the user has expressed no preference between them

#### Scenario: Preference names a language that does not validate the word
- **WHEN** the preferred ambiguity language is not among the languages that validate the render
- **THEN** it SHALL NOT be promoted, so the preference cannot drag a word into a language it does not belong to

#### Scenario: No dictionary evidence either way
- **WHEN** no installed language validates the render
- **THEN** the rotation order SHALL stand

#### Scenario: Selected text
- **WHEN** the user triggers conversion on selected text
- **THEN** the system SHALL apply the same ordering as for the keystroke path


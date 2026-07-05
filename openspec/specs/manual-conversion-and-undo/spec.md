# Manual Conversion and Undo

## Purpose

The system SHALL convert typed text between keyboard layouts when the user invokes the configured trigger, and SHALL support repeated invocations to cycle through candidate layouts and reverse the most recent conversion.

## Requirements

### Requirement: Convert the last typed word
The system SHALL convert the most recently typed word or the currently selected text when the manual trigger is invoked in an editable context. Because the trigger is an explicit user action, the system SHALL produce a conversion even when automatic detection would decline: if N-way detection finds a single unambiguous target the system SHALL convert to it, and otherwise the system SHALL convert to the first alternative candidate layout (the next installed layout whose rendering of the keystrokes differs from the current one).

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

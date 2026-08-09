## ADDED Requirements

### Requirement: Retain the best layout when candidates render identically
When two or more installed layouts render the input identically, the system SHALL offer them as a
single candidate — the cycle SHALL NOT gain a step that changes no visible character — and that
candidate SHALL carry the layout selected by the following order:

1. the layout of the unambiguous dictionary winner, when exactly one language validates the render;
2. otherwise, when more than one language validates it, the layout of the preferred ambiguity
   language, provided that language is among the validating ones and the preference is not
   "do not convert";
3. otherwise, the first such layout in the established rotation order.

This SHALL apply to candidates built from recorded keystrokes and to candidates built from a
selection alike.

#### Scenario: Word valid in only one of two identically-rendering languages
- **WHEN** the user triggers conversion of a word whose render is identical in Ukrainian and Russian but is a valid word only in Russian
- **THEN** the system SHALL produce that text once and SHALL switch to the Russian layout, regardless of which of the two layouts comes first in the input-source order

#### Scenario: Ambiguous word follows the preference
- **WHEN** the render is valid in both Ukrainian and Russian and the preferred ambiguity language is Russian
- **THEN** the system SHALL switch to the Russian layout

#### Scenario: Preference set to "do not convert"
- **WHEN** the render is valid in both languages and the ambiguity preference is "do not convert"
- **THEN** the system SHALL fall back to rotation order, since the user has expressed no preference between them

#### Scenario: No dictionary evidence either way
- **WHEN** no installed language validates the render
- **THEN** the system SHALL fall back to rotation order

#### Scenario: The cycle length is unchanged
- **WHEN** two layouts render the input identically
- **THEN** the candidate cycle SHALL contain one entry for them, so that repeated triggers never appear to do nothing

#### Scenario: Selected text
- **WHEN** the user triggers conversion on selected text whose candidates collapse in the same way
- **THEN** the system SHALL apply the same layout-selection order as for the keystroke path

## MODIFIED Requirements

### Requirement: Convert the last typed word
The system SHALL convert the most recently typed word or the currently selected text when the manual trigger is invoked in an editable context. Because the trigger is an explicit user action, the system SHALL produce a conversion even when automatic detection would decline: if N-way detection finds a single unambiguous target the system SHALL convert to it, and otherwise the system SHALL convert to the first alternative candidate layout (the next installed layout whose rendering of the keystrokes differs from the current one). Where several layouts render the input identically, the retained candidate's layout SHALL be chosen as specified in *Retain the best layout when candidates render identically*.

#### Scenario: Convert the last word through the buffer-based retype path
- **WHEN** the user types a word and invokes the manual trigger
- **THEN** the system SHALL retype the word using the converted text and preserve any trailing spaces that followed the word

#### Scenario: Convert selected text when no word buffer is available
- **WHEN** the user has selected text and invokes the manual trigger
- **THEN** the system SHALL convert the selected text in place using the clipboard-based fallback path when needed

#### Scenario: Act on an ambiguous word
- **WHEN** the user invokes the manual trigger on a word that automatic detection would leave unchanged (valid in the current language, or valid in more than one alternative language)
- **THEN** the system SHALL still convert the word to the first alternative candidate layout rather than leaving it unchanged, and SHALL record the candidate cycle so repeated invocations can advance through the remaining candidates

## ADDED Requirements

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

## MODIFIED Requirements

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

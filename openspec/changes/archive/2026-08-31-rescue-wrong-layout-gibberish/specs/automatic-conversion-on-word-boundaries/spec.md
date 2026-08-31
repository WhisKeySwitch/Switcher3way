## ADDED Requirements

### Requirement: Rescue gibberish typed in the wrong layout even when no dictionary knows the word
When a completed word validates in no installed language, the system SHALL NOT automatically keep it unconditionally. It SHALL first test the asymmetry that distinguishes wrong-layout jargon and names from legitimate unknown tokens, in either direction between scripts: the typed rendering must be gibberish in the typed language — no dictionary hit, no word within one edit (it is not a typo), and implausible as a word shape in that language — while a candidate rendering in another installed language is a plausible word shape there.

When the asymmetry holds, the system SHALL select the target as it does for dictionary words: a single plausible candidate language wins outright; when the plausible candidates are the Ukrainian/Russian pair, the configured ambiguity-preference language wins (and when that preference is off, the word SHALL be kept); when plausible candidates span scripts with no unique winner, the word SHALL be kept. The system SHALL convert the word and switch the layout to the selected language.

The plausibility test SHALL be derived from measurement over a fixture of real tokens — must-keep tokens of both scripts (proper nouns and acronyms typed in their own layout, identifiers, vowel-less abbreviations) against must-rescue wrong-layout jargon and names — and the measured false-conversion rate on the keep-side fixture SHALL gate the feature at zero: precision comes first, a missed rescue costs one manual trigger, a false rescue costs the user their sentence and their layout.

#### Scenario: Wrong-layout Cyrillic jargon converts to the ambiguity default
- **WHEN** the user types a word in the Latin layout whose typed rendering is gibberish in English (for example `fgrf`), the word validates in no installed language, and its Ukrainian and Russian renderings (`апка`) are plausible word shapes
- **THEN** the system SHALL convert the word and switch the layout to the ambiguity-preference language, and SHALL record the decision and its reason in the diagnostic log

#### Scenario: Wrong-layout English name converts to English
- **WHEN** the user types a word in a Cyrillic layout whose typed rendering is gibberish in that language (for example `Лншм`), the word validates in no installed language, and only its English rendering (`Kyiv`) is a plausible word shape
- **THEN** the system SHALL convert the word and switch the layout to English, regardless of the ambiguity-preference setting, and SHALL record the decision

#### Scenario: Plausible tokens in the typed language are kept
- **WHEN** the user types a token that no dictionary validates but whose typed rendering is a plausible word shape in the typed language or is within one edit of a word of that language (for example `Kyiv` typed in the English layout, or a typo like `emergancy`)
- **THEN** the system SHALL leave the text and layout unchanged, exactly as before this change, and SHALL record why

#### Scenario: Gibberish on both sides is kept
- **WHEN** the typed rendering is implausible in the typed language and no candidate rendering is plausible in its language either (for example `npm` or `zsh` typed in the English layout, or the Cyrillic abbreviation `кст` typed in a Cyrillic layout)
- **THEN** the system SHALL leave the text and layout unchanged

#### Scenario: Existing soft gates still veto first
- **WHEN** the typed token is all-caps, camelCase, mixed-script, or otherwise excluded by the soft gates (for example `SSO`, `PeopleOps`)
- **THEN** the system SHALL leave it unchanged without evaluating the rescue path

#### Scenario: Ambiguity preference off disables only the ambiguous rescue
- **WHEN** the ambiguity-preference setting is off and the user types wrong-layout gibberish whose plausible candidates are the Ukrainian/Russian pair
- **THEN** the system SHALL leave the word unchanged, matching the setting's existing contract for ambiguous words, while a rescue with a single plausible candidate language SHALL still convert

#### Scenario: A rescued word remains manually reversible
- **WHEN** a word was converted by the rescue path and the user taps the manual trigger
- **THEN** the system SHALL cycle the word back through the candidate layouts to its original form, exactly as for any other automatic conversion

## MODIFIED Requirements

### Requirement: Validate words offline against bundled dictionaries
The Windows build SHALL validate candidate words against Hunspell dictionaries bundled with the application, so that detection works with no network access and no dependency on the language packs a particular machine happens to have installed.

A bundled dictionary SHALL carry a licence permitting redistribution inside this application, and its licence text SHALL ship alongside it. Where a dictionary is offered under several licences, the permissive branch SHALL be the one relied upon and recorded.

Adding a language SHALL NOT reduce detection quality for the languages already supported. Because every additional language is another opportunity for a mistyped word to be a real word somewhere, the effect of adding one SHALL be measured against the existing precision corpora before it ships, in the configuration least favourable to the candidate rather than the most.

#### Scenario: Validation works with no network
- **WHEN** the application validates a candidate word
- **THEN** it SHALL consult the bundled dictionaries only, without network access

#### Scenario: A language's shape rules are supplied with its dictionary
- **WHEN** a language is bundled
- **THEN** the data its heuristics depend on — the letters it uses and which of them are vowels — SHALL be supplied for that language, since a heuristic that silently has no data for a language answers for it anyway

#### Scenario: A language whose words can lack vowels
- **WHEN** a bundled language contains ordinary words with no vowel — as Serbian does, through syllabic R, in everyday words such as `крв`, `прст` and `врх`
- **THEN** the plausibility heuristic SHALL account for that, so those words are not read as unpronounceable and converted into another language
- **AND** the check SHALL consider how common such words are, not only how many of them there are: counting distinct words made Serbian's syllabic R look negligible at 0.14% while the words behind that figure are among the most frequent in the language

#### Scenario: Adding a language is priced before it ships
- **WHEN** a new language is proposed for bundling
- **THEN** its effect on the existing precision corpora SHALL be measured, and it SHALL NOT ship if the languages already supported lose accuracy
- **AND** the measurement SHALL place the candidate in its worst case — for instance rendering it through a keyboard layout it does not use, so that its output collides with an existing language instead of diverging from it

#### Scenario: A dictionary without a redistributable licence is declined
- **WHEN** the only available dictionary for a language is licensed in a way that cannot be redistributed inside this application
- **THEN** that language SHALL NOT be bundled, however desirable it is, and the reason SHALL be recorded so the decision is not revisited from scratch

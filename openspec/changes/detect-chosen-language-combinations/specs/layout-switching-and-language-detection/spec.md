# Spec Delta

## MODIFIED Requirements

### Requirement: Discover installed layouts and their languages
The system SHALL enumerate the installed keyboard input sources and determine their language codes so that conversion decisions can be made against the available layouts.

Automatic detection SHALL consider only layouts whose language is a *supported detection language*: one for which the system carries the per-language knowledge detection relies on (its vowels, a dictionary self-test, and a list of the short words its speakers type) and whose combinations with the other supported languages have passed the measurement gate below. Detection SHALL run over whichever supported languages the user has enabled, in any combination, and SHALL NOT require any particular language other than the one being typed.

#### Scenario: Resolve available layouts at runtime
- **WHEN** the application needs to convert or switch layouts
- **THEN** the system SHALL inspect the currently installed input sources and their language metadata

#### Scenario: Handle layouts without a known language
- **WHEN** an installed layout does not expose a usable language code
- **THEN** the system SHALL ignore that layout for language-based detection

#### Scenario: Detect over any combination of supported languages
- **WHEN** the user has enabled layouts for two or three supported languages that do not include Ukrainian or Russian (for example English and Bulgarian, or English, German and French)
- **THEN** the system SHALL detect wrong-layout words among exactly those languages, with the same safety rules it applies to English, Ukrainian and Russian

#### Scenario: Leave an unsupported language out of automatic detection
- **WHEN** an enabled layout's language is not a supported detection language, even if the system dictionary covers it
- **THEN** the system SHALL NOT convert into or out of that language automatically, SHALL still offer that layout in the manual trigger's cycle, and SHALL record once in the debug log that the language was skipped and why

#### Scenario: A layout whose language the spell checker cannot judge
- **WHEN** an enabled layout's language has no dictionary the system can consult (for example the Byelorussian or Kazakh layout on a Mac without a dictionary for that language), and so every string would read as valid in it
- **THEN** the system SHALL treat the language as unsupported, SHALL NOT let it keep or convert any word, and SHALL record the reason once in the debug log

## ADDED Requirements

### Requirement: Transliterating layouts are not automatic targets for newly supported languages
A layout that renders Latin keystrokes as a letter-for-letter transliteration into another script (for example Bulgarian Phonetic, where `reda` renders as `реда`) turns ordinary English typos into valid words of that language. For languages admitted by this change, the system SHALL NOT automatically convert a word into such a layout. Layouts of Russian and Ukrainian SHALL keep their existing behaviour.

#### Scenario: English typo on a Bulgarian Phonetic setup
- **WHEN** the user has English and Bulgarian Phonetic enabled, types an English word with a typo on the English layout, and the Bulgarian Phonetic rendering is a valid Bulgarian word
- **THEN** the system SHALL leave the text and layout unchanged and SHALL record the reason

#### Scenario: A transliterating layout still works as the layout being typed in
- **WHEN** the active layout is Bulgarian Phonetic and the user types a word that is valid only in another enabled language
- **THEN** the system SHALL evaluate and convert the word exactly as it would from any other layout

#### Scenario: The manual trigger still reaches a transliterating layout
- **WHEN** the user presses the manual trigger on a word
- **THEN** the candidate cycle SHALL include the transliterating layout like any other enabled layout

#### Scenario: A standard layout of the same language is still a target
- **WHEN** the user has both the standard Bulgarian layout and Bulgarian Phonetic enabled
- **THEN** automatic conversion into Bulgarian SHALL use the standard layout

### Requirement: A language is admitted only after its combinations are measured
A language SHALL become a supported detection language only after every two- and three-language combination of it with the other supported languages has been measured against the real system dictionaries and the real layout tables, and every combination has met all of the following:

- correctly typed prose in each language of the combination, typed on its own layout, converts no word;
- one-edit typos (dropped, doubled and transposed letters) of prose in each language of the combination, typed on that language's own layout, convert at a rate no higher than the highest rate the shipped English/Ukrainian/Russian combination shows for its own languages, measured the same way in the same run;
- no wrong-layout word that the system treats as settled — a conversion or rescue with a single winning language — converts into a different word than the one intended. A tie the preference settled into a different word is reported separately, because the system marks such a word as defaulted and phrase correction owns it.

Recall SHALL be reported for each combination but SHALL NOT gate admission. A language whose default layout gives nothing to detect SHALL be declined, with the measurement recorded.

#### Scenario: A combination fails the gate
- **WHEN** any combination containing a candidate language converts correctly typed prose, or converts typos of any of its languages above the shipped baseline
- **THEN** the language SHALL NOT be admitted, and the measurement and reason SHALL be recorded in the change

#### Scenario: The measurement is re-runnable
- **WHEN** a developer runs the combination measurement on a Mac with the relevant dictionaries
- **THEN** it SHALL print each combination's typo, keep and recall figures, and SHALL fail if any admitted combination misses the gate

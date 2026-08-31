## ADDED Requirements

### Requirement: One dictionary verdict per word per decision
Within a single conversion decision, the system SHALL ask the dictionary about a given rendering at most once and SHALL act on that verdict throughout the decision. The recorded diagnostic dump and the decision outcome SHALL therefore never contradict each other about a word's validity.

#### Scenario: A flip-flopping dictionary cannot split one decision
- **WHEN** the dictionary would answer differently on a repeated query for the same word during one decision
- **THEN** the decision SHALL be based on the single verdict actually taken, and the diagnostic record SHALL reflect that same verdict

### Requirement: Quarantine a dictionary that fails its canaries
The system SHALL periodically verify each language's dictionary against two canaries — a common word of the language that must validate, and a keyboard-mash string that must not. When a probe fails, the system SHALL treat that language's dictionary as unavailable for conversion decisions until a later probe passes, SHALL log the quarantine and the recovery unconditionally, and SHALL prefer doing nothing over acting on a dictionary known to be answering incorrectly.

#### Scenario: An accept-everything episode is caught
- **WHEN** a language's dictionary validates the keyboard-mash canary
- **THEN** the language SHALL be excluded from detection (no conversions into or out of it on dictionary evidence) until a subsequent probe passes, and the episode SHALL be visible in the log

#### Scenario: A reject-everything episode is caught
- **WHEN** a language's dictionary rejects the common-word canary
- **THEN** the language SHALL be excluded from detection until a subsequent probe passes, rather than silently eating conversions word by word

#### Scenario: A healthy dictionary is untouched
- **WHEN** the probes pass
- **THEN** validation behaves exactly as before, and the probe cost stays off the per-keystroke path (probes run on first use and on a cooldown interval, not per word)

### Requirement: Confirm the dictionary before acting on it
Before converting on dictionary evidence, the system SHALL confirm that the language's dictionary is answering correctly at that moment, and SHALL decline the conversion when it is not. A periodic health check alone SHALL NOT be treated as sufficient, because the interval between checks is a window in which a newly-incorrect dictionary would convert a name into keyboard mash and move the layout with it.

#### Scenario: An episode that began after the last check is caught
- **WHEN** a language's dictionary passed its canaries earlier but has since begun answering incorrectly, and a word's only winner is that language
- **THEN** the system SHALL re-check that dictionary before acting, SHALL leave the text and layout unchanged, and SHALL record that the dictionary failed its self-check

#### Scenario: The confirmation stays off the per-word path
- **WHEN** many words are evaluated and none results in a conversion
- **THEN** the confirmation SHALL not be performed per word, and repeated confirmations within a short freshness window SHALL reuse the verdict already taken

## MODIFIED Requirements

### Requirement: Rewrite typed text in place
The Windows build SHALL replace the mistyped word with its converted form by erasing the original
characters and inserting the corrected Unicode text, with a clipboard-based fallback for selected
text. When a real (user-originated, non-synthetic) keystroke is detected while a replacement is in
progress, the Windows build SHALL abort the replacement, restore any characters it has already
erased, and record no conversion — so that neither a single-word rewrite nor a multi-word phrase
correction can leave the on-screen text partially deleted.

The Windows build SHALL inject the erase and insert streams at a rate the target application can
consume. Above a threshold length it SHALL insert the replacement as a single clipboard paste rather
than as one event per character, because per-character injection of long text is both slow and the form
the target mis-renders. Where it borrows the clipboard it SHALL restore the previous text afterwards,
and only once the paste has been observed on screen.

The Windows build SHALL NOT report a replacement as successful on the strength of the input events
having been accepted. It SHALL compare the text that landed against the text it intended to produce,
and where they differ it SHALL report the replacement as failed, restore the text to its pre-rewrite
state where it can, and record the intended and landed text so the discrepancy is diagnosable.

Where the landed text cannot be read at all, the Windows build SHALL record the replacement as
unverified and SHALL treat it as applied: it SHALL NOT repair the text, SHALL NOT present a failure to
the user, and SHALL allow a cycle to continue. An unreadable target is an absence of evidence, not
evidence of failure — several applications, including Chromium-based ones, expose no readable text
until an accessibility client has asked once, and treating that as a fault would put an error in front
of conversions that demonstrably worked.

#### Scenario: Rewrite a buffered word
- **WHEN** a conversion is applied to a buffered word
- **THEN** the system SHALL erase the original characters and insert the converted text, preserving any trailing spaces

#### Scenario: Abort and restore on concurrent typing
- **WHEN** the user types a real key while a single-word or multi-word segment replacement is being injected
- **THEN** the system SHALL stop injecting, restore the characters it already erased, leave the layout unchanged, and treat the conversion as not having happened

#### Scenario: Surface protected targets rather than failing silently
- **WHEN** the foreground window cannot receive synthesized input because it runs at a higher integrity level
- **THEN** the system SHALL NOT report a successful conversion and SHALL make the limitation observable

#### Scenario: A replacement that lands mangled is not a success
- **WHEN** every injected event is accepted but the text that lands differs from the text the replacement intended
- **THEN** the system SHALL report the replacement as failed, SHALL NOT show feedback claiming a conversion, and SHALL record both the intended and the landed text

#### Scenario: A large replacement is not corrupted by its own injection rate
- **WHEN** a replacement erases and reinserts a selection of at least fifty characters
- **THEN** the text that lands SHALL match the text intended, character for character

#### Scenario: A long replacement borrows the clipboard and gives it back
- **WHEN** a replacement longer than the paste threshold is applied while the user has text on the clipboard
- **THEN** the replacement SHALL be inserted as one paste, and the user's previous clipboard text SHALL be on the clipboard again afterwards

#### Scenario: A short replacement leaves the clipboard alone
- **WHEN** a replacement at or below the paste threshold is applied
- **THEN** it SHALL be typed rather than pasted, and the clipboard SHALL NOT be touched

#### Scenario: A replacement across a change of script is not corrupted
- **WHEN** a replacement switches the layout from one script to another immediately before inserting its characters
- **THEN** the text that lands SHALL match the text intended, character for character

#### Scenario: An unreadable result is recorded, not treated as a failure
- **WHEN** the target application exposes no way to read back the text that landed
- **THEN** the system SHALL record the replacement as unverified, SHALL NOT repair the text, SHALL NOT show the user a failure, and SHALL allow a cycle to continue from it

### Requirement: Provide manual conversion and undo
The Windows build SHALL let the user convert the last word or selection on demand via a configurable
trigger, cycle through candidate layouts on repeated invocations, and restore the original text and
pre-conversion layout when the cycle completes. When the word is ambiguous, the first candidate
offered SHALL be the preferred ambiguity language (when it is one of the candidates), so a single
trigger invocation yields the same result automatic conversion would. The same trigger SHALL also
cancel an automatic conversion: an auto-fix seeds a single-candidate cycle whose candidate is
already on screen, so the first trigger invocation after it restores the original text and layout.

A cycle SHALL NOT continue from text the build has established is wrong. When a step of the cycle is
reported as failed, the Windows build SHALL end the cycle rather than advance it, so that a corrupted
result is never used as the input to a further conversion. A step that merely could not be read back
SHALL NOT end the cycle.

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

#### Scenario: A failed step ends the cycle instead of compounding
- **WHEN** a step of the cycle is reported as failed
- **THEN** the system SHALL end the cycle, and a subsequent trigger invocation SHALL start afresh from what is on screen rather than continue from the failed step's assumptions

#### Scenario: An unverified step does not interrupt cycling
- **WHEN** a step of the cycle lands in a target whose text cannot be read back
- **THEN** the system SHALL continue the cycle on the next trigger invocation, so that cycling works in applications that expose no readable text

## MODIFIED Requirements

### Requirement: Rewrite typed text in place
The Windows build SHALL replace the mistyped word with its converted form by removing the original
characters and inserting the corrected Unicode text, with a clipboard-based fallback for selected
text. It MAY remove the original either by erasing it or by selecting the range and replacing it, so
long as the outcome is verified; the choice is an implementation matter except that a method whose lost
events silently delete the wrong text SHALL NOT be preferred over one whose lost events produce a
detectable wrong result. When a real (user-originated, non-synthetic) keystroke is detected while a
replacement is in progress, the Windows build SHALL abort the replacement, restore any characters it has
already removed, and record no conversion — so that neither a single-word rewrite nor a multi-word phrase
correction can leave the on-screen text partially deleted.

The Windows build SHALL inject its input at a rate the target application can consume, and SHALL NOT
spend materially longer doing so than that rate requires. A replacement at the maximum selection length
SHALL complete within about a second and a half, and a replacement of a single word within a quarter of a
second, measured from the first injected event to the verified result. Correctness that takes several
seconds to arrive is a different feature from correctness that arrives promptly: the user is typing, and
a rewrite slow enough to type into is a rewrite that will be typed into.

Above a threshold length it SHALL insert the replacement as a single clipboard paste rather
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
- **THEN** the system SHALL remove the original characters and insert the converted text, preserving any trailing spaces

#### Scenario: Abort and restore on concurrent typing
- **WHEN** the user types a real key while a single-word or multi-word segment replacement is being injected
- **THEN** the system SHALL stop injecting, restore the characters it already removed, leave the layout unchanged, and treat the conversion as not having happened

#### Scenario: Surface protected targets rather than failing silently
- **WHEN** the foreground window cannot receive synthesized input because it runs at a higher integrity level
- **THEN** the system SHALL NOT report a successful conversion and SHALL make the limitation observable

#### Scenario: A replacement that lands mangled is not a success
- **WHEN** every injected event is accepted but the text that lands differs from the text the replacement intended
- **THEN** the system SHALL report the replacement as failed, SHALL NOT show feedback claiming a conversion, and SHALL record both the intended and the landed text

#### Scenario: A large replacement is not corrupted by its own injection rate
- **WHEN** a replacement removes and reinserts a selection of at least fifty characters
- **THEN** the text that lands SHALL match the text intended, character for character

#### Scenario: A replacement at the selection limit completes promptly
- **WHEN** a replacement is applied to a selection at the maximum supported length
- **THEN** it SHALL complete within about a second and a half from the first injected event to the verified result

#### Scenario: A single-word replacement stays fast
- **WHEN** a conversion is applied to a word of about five characters
- **THEN** it SHALL complete within about a quarter of a second, so the common case is not slowed by accommodating the long one

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

## ADDED Requirements

### Requirement: Show the conversion itself at the caret
When the conversion-feedback feature is enabled and a conversion succeeds, the system SHALL display a
transient badge next to the text caret showing what was replaced: the originally typed form, a
direction indicator, and the converted form, together with a hint naming the configured manual trigger
as the way to undo it. The badge SHALL name the trigger the user has actually configured, not a fixed
key. It SHALL appear for automatic conversions, for manual trigger conversions, and for phrase
corrections, but SHALL NOT appear on the final restore-to-original step of the candidate cycle, which
is the user rejecting a conversion rather than receiving one.

#### Scenario: Automatic conversion succeeds
- **WHEN** an automatic conversion replaces a word and the conversion-feedback feature is enabled
- **THEN** the system SHALL display a badge showing the typed form, the converted form, and the undo hint next to the caret, and SHALL fade it out after a short hold

#### Scenario: Cycle returns to the original text
- **WHEN** repeated manual trigger invocations advance past the last candidate and restore the original text
- **THEN** the system SHALL NOT display a conversion badge for that step

#### Scenario: Feedback disabled
- **WHEN** the conversion-feedback setting is off
- **THEN** the system SHALL display no conversion badge, and the existing flag-on-layout-change behavior SHALL be unaffected

#### Scenario: Trigger key changed
- **WHEN** the user has configured a manual trigger other than the default
- **THEN** the undo hint in the badge SHALL name the configured trigger

### Requirement: Fall back to the window anchor when the caret is unresolvable
When the caret rectangle cannot be resolved for the focused application, the system SHALL still show
the conversion badge, anchored to the focused window, rather than suppressing the feedback entirely —
the user needs to know what was changed even where the exact caret position is unavailable.

#### Scenario: Application exposes no caret geometry
- **WHEN** a conversion succeeds in an application whose caret rectangle cannot be resolved through Accessibility
- **THEN** the system SHALL display the conversion badge anchored to the focused window

#### Scenario: No focused window either
- **WHEN** neither a caret rectangle nor a focused window can be resolved
- **THEN** the system SHALL skip the badge for that conversion

## MODIFIED Requirements

### Requirement: Suppress caret flag in sensitive contexts
The caret flag and the conversion badge SHALL NOT be shown while secure input is active, while the
focused control is detected as a password field by the focused-element password check, while the
frontmost application is a remote-desktop client, while the frontmost application is on the denied-apps
list, or over the app's own windows. The badge carries the text that was typed, so its suppression
rules SHALL be at least as strict as those governing conversion itself.

#### Scenario: Typing in a password field
- **WHEN** the layout changes or a conversion occurs while secure input is active
- **THEN** no caret badge is displayed

#### Scenario: Typing in a field detected as a password field
- **WHEN** the focused control is reported as a password field by the focused-element check, even with no secure-input flag set
- **THEN** no caret badge and no conversion badge is displayed

#### Scenario: Frontmost application is excluded
- **WHEN** the frontmost application is a remote-desktop client or is on the denied-apps list
- **THEN** no caret badge and no conversion badge is displayed

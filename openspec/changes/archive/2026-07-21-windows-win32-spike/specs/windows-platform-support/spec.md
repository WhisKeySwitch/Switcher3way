## MODIFIED Requirements

### Requirement: Switch the foreground application's layout
The Windows build SHALL change the active keyboard layout of the foreground application,
accounting for the per-thread nature of the Windows input language, and SHALL confirm the
change took effect rather than assuming a single switch mechanism always succeeds.

#### Scenario: Change the layout of the active window
- **WHEN** the system decides to convert a word to another language
- **THEN** the system SHALL activate the corresponding layout for the foreground application so continued typing uses that layout

#### Scenario: Confirm the switch and fall back when it does not take effect
- **WHEN** the system requests a foreground-layout change through its primary mechanism
- **THEN** the system SHALL determine whether the active layout actually changed, and SHALL attempt an alternative switch mechanism when the primary request did not take effect

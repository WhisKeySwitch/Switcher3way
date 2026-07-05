# Delta: Layout Switching and Language Detection (rework-manual-trigger-nway)

## MODIFIED Requirements

### Requirement: Support direct manual layout switching
The system SHALL allow the user to switch directly to a specific layout, to cycle through an ordered list of candidate layouts, and to restore a previously recorded layout. Manual switching SHALL NOT depend on a fixed two-layout pair.

#### Scenario: Switch to an explicit layout
- **WHEN** the user requests a specific layout through the app’s switching logic
- **THEN** the system SHALL select that input source through the macOS input-source API

#### Scenario: Cycle to the next candidate layout
- **WHEN** the user advances the manual trigger through the candidate layouts
- **THEN** the system SHALL select the next candidate input source in the ordered cycle, wrapping back to the pre-conversion layout after the last candidate

#### Scenario: Restore the recorded previous layout
- **WHEN** the app needs to undo a conversion
- **THEN** the system SHALL re-select the exact layout that was recorded as active before the conversion, rather than selecting the alternate of a configured pair

#### Scenario: Fallback switching where per-layout rendering is unavailable
- **WHEN** keystrokes arrive pre-rendered as characters (e.g. through a remote-desktop client) so candidate rendering across layouts is not possible
- **THEN** the system SHALL advance the local layout to the next installed input source as a deterministic fallback

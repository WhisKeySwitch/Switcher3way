## MODIFIED Requirements

### Requirement: Persist user preferences
The system SHALL store settings in the app’s persistent defaults so that preferences survive app restarts and relaunches. Preferences cover trigger behavior, auto-conversion, and the exception lists that govern when conversion is allowed or forced. The manual trigger SHALL NOT require a user-selected layout pair; any `layout1ID`/`layout2ID` values retained in defaults SHALL be treated as dormant rollback insurance and SHALL NOT drive trigger behavior.

Losing stored preferences SHALL NOT be silent. Where settings are held in a file that can fail to load as a whole, the system SHALL distinguish "there is nothing stored yet" from "there is something stored and it could not be read", SHALL report the second, and SHALL NOT overwrite the unreadable data with defaults. Reporting SHALL NOT depend on a setting read from the same store, since that setting is unavailable in precisely the case that needs reporting.

#### Scenario: Save a changed trigger setting
- **WHEN** the user changes the conversion trigger or related options
- **THEN** the system SHALL persist the new value in the application defaults

#### Scenario: Save a changed auto-conversion toggle
- **WHEN** the user enables or disables automatic conversion or related features
- **THEN** the system SHALL persist the new toggle state for future sessions

#### Scenario: Legacy pair keys are ignored
- **WHEN** `layout1ID` or `layout2ID` still hold values from a previous version
- **THEN** the manual trigger SHALL ignore them and behave identically to a fresh install with no pair configured

#### Scenario: A first run has nothing stored
- **WHEN** the application starts and no settings have ever been saved
- **THEN** it SHALL use defaults without reporting a failure, because nothing was lost

#### Scenario: Stored settings that cannot be read are reported, not discarded
- **WHEN** stored settings exist but cannot be loaded — malformed, truncated, unreadable, or written by a version this build cannot parse
- **THEN** the system SHALL record the failure through the always-on diagnostic path, not the one gated by a stored preference
- **AND** SHALL preserve the unreadable data under a distinct name rather than replacing it
- **AND** SHALL inform the user, because the alternative is that carefully configured exception lists disappear with no indication that anything happened

#### Scenario: A failed load does not become a permanent erasure
- **WHEN** settings failed to load and the user subsequently changes any preference
- **THEN** saving SHALL NOT silently overwrite the preserved original with defaults

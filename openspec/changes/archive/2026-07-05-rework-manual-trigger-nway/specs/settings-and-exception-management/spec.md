# Delta: Settings and Exception Management (rework-manual-trigger-nway)

## MODIFIED Requirements

### Requirement: Persist user preferences
The system SHALL store settings in the app’s persistent defaults so that preferences survive app restarts and relaunches. Preferences cover trigger behavior, auto-conversion, and the exception lists that govern when conversion is allowed or forced. The manual trigger SHALL NOT require a user-selected layout pair; any `layout1ID`/`layout2ID` values retained in defaults SHALL be treated as dormant rollback insurance and SHALL NOT drive trigger behavior.

#### Scenario: Save a changed trigger setting
- **WHEN** the user changes the conversion trigger or related options
- **THEN** the system SHALL persist the new value in the application defaults

#### Scenario: Save a changed auto-conversion toggle
- **WHEN** the user enables or disables automatic conversion or related features
- **THEN** the system SHALL persist the new toggle state for future sessions

#### Scenario: Legacy pair keys are ignored
- **WHEN** `layout1ID` or `layout2ID` still hold values from a previous version
- **THEN** the manual trigger SHALL ignore them and behave identically to a fresh install with no pair configured

### Requirement: Display names follow the interface language
Names rendered by the app for applications (exceptions list) and any keyboard-layout names it displays SHALL be consistent with the app's effective interface language. When the interface language matches the macOS system language, system-localized names SHALL be used; when it differs, language-neutral names SHALL be used instead (apps from the bundle's on-disk name, layouts from the input-source ID).

#### Scenario: English interface on a Russian-language system
- **WHEN** the macOS system language is Russian, the app's interface language is English, and the user opens the exceptions Apps list
- **THEN** app names SHALL be shown in their language-neutral on-disk form (e.g. "Terminal"), not Russian system-localized names

#### Scenario: Interface language matches the system
- **WHEN** the app's interface language is the system default and the app displays a keyboard-layout name
- **THEN** the layout SHALL show its system-localized name

## REMOVED Requirements

### Requirement: Merge manual layout pair into a single row
**Reason**: The manual trigger is now fully N-way and cycles through candidate layouts, so there is no user-configurable two-layout pair to present. The General tab no longer contains layout pickers.
**Migration**: None required. The `layout1ID`/`layout2ID` defaults keys remain in storage as dormant rollback insurance but are no longer read for trigger behavior; users who previously set a pair need take no action.

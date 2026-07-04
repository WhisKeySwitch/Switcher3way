# Delta: Settings and Exception Management (fix-display-language-and-about)

## ADDED Requirements

### Requirement: Display names follow the interface language
Names rendered by the app for keyboard layouts (manual-pair popups) and applications (exceptions list) SHALL be consistent with the app's effective interface language. When the interface language matches the macOS system language, system-localized names SHALL be used; when it differs, language-neutral names SHALL be used instead (layouts from the input-source ID, apps from the bundle's on-disk name).

#### Scenario: English interface on a Russian-language system
- **WHEN** the macOS system language is Russian, the app's interface language is English, and the user opens the exceptions Apps list
- **THEN** app names SHALL be shown in their language-neutral on-disk form (e.g. "Terminal"), not Russian system-localized names

#### Scenario: Interface language matches the system
- **WHEN** the app's interface language is the system default and the user opens the manual-pair popups
- **THEN** layouts SHALL show their system-localized names

### Requirement: Centered About tab
The About tab SHALL present the app name and version centered horizontally in the tab.

#### Scenario: Opening the About tab
- **WHEN** the user opens Settings ▸ About
- **THEN** the app name and version SHALL appear centered in the window

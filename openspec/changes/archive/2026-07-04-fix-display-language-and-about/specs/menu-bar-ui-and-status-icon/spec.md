# Delta: Menu Bar UI and Status Icon (fix-display-language-and-about)

## MODIFIED Requirements

### Requirement: Status-first menu header
The status menu SHALL open with a header row showing the currently active layout (short badge plus layout name), a one-line reminder of the manual trigger, and the app version. The layout name SHALL be consistent with the app's effective interface language: when the interface language differs from the macOS system language, a language-neutral name derived from the input-source ID SHALL be shown instead of the system-localized name.

#### Scenario: Header reflects the active layout
- **WHEN** the user opens the menu while the U.S. layout is active
- **THEN** the header SHALL show the U.S. layout's badge and name, the trigger reminder, and the version

#### Scenario: Interface language differs from system language
- **WHEN** the macOS system language is Russian and the app's interface language is English
- **THEN** the header SHALL show the layout's language-neutral name (e.g. "Russian"), not the Russian system-localized name

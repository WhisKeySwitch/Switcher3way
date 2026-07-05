# Delta: In-App Help (add-in-app-help)

## ADDED Requirements

### Requirement: Help is bundled and works offline
The app bundle SHALL contain the full user guide as pre-rendered HTML for every language the guide exists in (currently English, Ukrainian, Russian), generated at build time from `docs/user-guide*.md`. Displaying help SHALL NOT require network access.

#### Scenario: Offline help
- **WHEN** the user opens Help with no network connection
- **THEN** the full user guide SHALL display from bundled resources

### Requirement: Help is generated from the repository manuals
The build SHALL generate the bundled help from `docs/user-guide*.md` on every build and SHALL fail if a source guide is missing, so that in-app help cannot drift from the repository documentation.

#### Scenario: Manual edited
- **WHEN** a maintainer edits `docs/user-guide.md` and rebuilds the app
- **THEN** the next build's bundled help SHALL contain the edit with no additional step

#### Scenario: Source guide missing
- **WHEN** a source guide file is absent at build time
- **THEN** the build SHALL fail with an explanatory error rather than bundle stale or partial help

### Requirement: Help language follows the interface language
The help window SHALL display the guide matching the app's effective interface language when a translation exists (uk, ru) and SHALL fall back to English otherwise. Language cross-links inside the guide SHALL navigate between the bundled translations.

#### Scenario: Ukrainian interface
- **WHEN** the interface language resolves to Ukrainian and the user opens Help
- **THEN** the Ukrainian guide SHALL be shown

#### Scenario: Language without a translation
- **WHEN** the interface language resolves to a language with no guide translation (e.g. German)
- **THEN** the English guide SHALL be shown

### Requirement: Help window behavior
The help window SHALL render the guide with working in-page anchors, SHALL be resizable and reusable (reopening brings the existing window forward), and SHALL open external links in the user's default browser rather than inside the help window.

#### Scenario: External link
- **WHEN** the user clicks a link to an external website inside the help window
- **THEN** the link SHALL open in the default browser and the help window SHALL keep showing the guide

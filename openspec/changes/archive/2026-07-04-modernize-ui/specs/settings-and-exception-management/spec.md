# Delta: Settings and Exception Management (modernize-ui)

## ADDED Requirements

### Requirement: Present Settings as a native macOS 13+ preferences window
The Settings window SHALL use toolbar-style icon tabs in the order General, Auto-fix, Advanced, About, and SHALL present its controls as grouped form sections using switches (NSSwitch) for boolean options instead of bare checkboxes. The tab previously named "Auto-conversion" SHALL be labeled "Auto-fix".

#### Scenario: Opening Settings shows toolbar tabs
- **WHEN** the user opens the Settings window
- **THEN** the window SHALL show icon toolbar tabs labeled General, Auto-fix, Advanced, and About in that order, with the active tab highlighted

#### Scenario: Boolean options render as switches
- **WHEN** any tab displays a boolean preference (e.g. launch at login, automatic conversion)
- **THEN** the option SHALL be rendered as a switch inside a grouped section, and toggling it SHALL persist the value exactly as the previous checkbox did

### Requirement: Promote master enable to a status card
The General tab SHALL present the master on/off state as a status card at the top of the form showing the current state ("Switcher3way is On/Off"), a one-line trigger reminder, and a switch that controls the existing enable preference.

#### Scenario: Toggling the status card
- **WHEN** the user flips the status card's switch
- **THEN** the enable preference SHALL be persisted, the card title SHALL update to reflect the new state, and monitoring SHALL start or stop as it does today

### Requirement: Merge manual layout pair into a single row
The General tab SHALL present the manual-trigger layout pair as one "toggles between X ⇄ Y" row with two inline layout popups, replacing the separate Layout 1 / Layout 2 rows, with an explanatory footnote stating that auto-fix covers all installed layouts and this pair applies only to the manual trigger.

#### Scenario: Changing either side of the pair
- **WHEN** the user changes either popup in the pair row
- **THEN** the corresponding existing layout preference (layout1ID or layout2ID) SHALL be persisted unchanged in key and format

### Requirement: Unified exceptions list with segmented filter
The Auto-fix tab SHALL present the three exception lists (denied apps, never-convert words, always-convert words) as one full-height list controlled by a segmented filter whose segments show live item counts, with a search field that filters the visible list and an explicit add button ("+ Add app…" for the Apps segment, a text-entry affordance for the word segments).

#### Scenario: Switching segments
- **WHEN** the user selects the "Never convert" segment
- **THEN** the list SHALL show only never-convert words and the add affordance SHALL switch to word entry

#### Scenario: Adding an app via the picker
- **WHEN** the user clicks "+ Add app…" on the Apps segment and chooses an application
- **THEN** the app SHALL be appended to the denied-app list using the same persisted representation as today

#### Scenario: Searching within a segment
- **WHEN** the user types in the search field
- **THEN** the list SHALL show only entries matching the query, and clearing the query SHALL restore the full list

### Requirement: Badge protected entries
Protected password-manager entries in the Apps list SHALL be visibly marked with an "always off" badge and SHALL NOT be removable, replacing the previous unexplained gray styling.

#### Scenario: Attempting to remove a protected entry
- **WHEN** the user selects a protected password-manager row
- **THEN** the remove affordance SHALL be disabled and the row SHALL display the "always off" badge

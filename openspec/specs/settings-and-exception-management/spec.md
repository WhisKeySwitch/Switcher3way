# Settings and Exception Management

## Purpose

The system SHALL expose and persist user preferences for trigger behavior, auto-conversion, and the exception lists that govern when conversion is allowed or forced.
## Requirements
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

### Requirement: Manage exception lists
The system SHALL maintain separate lists for denied applications, denied words, and always-convert words so that conversion behavior can be tailored per context.

#### Scenario: Add a denied application
- **WHEN** the user adds an application to the denied-app list
- **THEN** the system SHALL ensure automatic conversion is skipped in that application

#### Scenario: Add an exception word
- **WHEN** the user adds a word to the denied-word or always-convert list
- **THEN** the system SHALL use that exception during later conversion decisions

### Requirement: Keep protected defaults intact
The system SHALL preserve the protected password-manager applications that are always treated as denied for automatic conversion.

#### Scenario: Preserve protected application entries
- **WHEN** the user updates the denied-app list
- **THEN** the system SHALL keep the protected password-manager entries in effect

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

### Requirement: Display names follow the interface language
Names rendered by the app for applications (exceptions list) and any keyboard-layout names it displays SHALL be consistent with the app's effective interface language. When the interface language matches the macOS system language, system-localized names SHALL be used; when it differs, language-neutral names SHALL be used instead (apps from the bundle's on-disk name, layouts from the input-source ID).

#### Scenario: English interface on a Russian-language system
- **WHEN** the macOS system language is Russian, the app's interface language is English, and the user opens the exceptions Apps list
- **THEN** app names SHALL be shown in their language-neutral on-disk form (e.g. "Terminal"), not Russian system-localized names

#### Scenario: Interface language matches the system
- **WHEN** the app's interface language is the system default and the app displays a keyboard-layout name
- **THEN** the layout SHALL show its system-localized name

### Requirement: Centered About tab
The About tab SHALL present the app name and version centered horizontally in the tab.

#### Scenario: Opening the About tab
- **WHEN** the user opens Settings ▸ About
- **THEN** the app name and version SHALL appear centered in the window

### Requirement: Auto-fix master toggle without a beta badge
The Auto-fix tab's master toggle ("Fix layout automatically as I type") SHALL be presented without a beta badge. Toggling it SHALL persist the automatic-conversion preference exactly as before.

#### Scenario: Master toggle shows no beta badge
- **WHEN** the user opens Settings ▸ Auto-fix
- **THEN** the "Fix layout automatically as I type" row SHALL display its title and description without a "BETA" badge
- **AND** toggling the switch SHALL persist the automatic-conversion preference and start/stop auto-conversion exactly as it did before

### Requirement: Experimental toggles live at the top of the Advanced tab
The "Show layout flag at the cursor" toggle and the "Remote Desktop mode" toggle SHALL be presented at the top of the Advanced tab, above the debug-logging controls, and SHALL NOT appear in the Auto-fix tab. Each SHALL keep its beta labeling, its persisted preference key, and its behavior. The remote-desktop toggle SHALL continue to appear only when its beta flag is enabled.

#### Scenario: Advanced tab shows the relocated toggles first
- **WHEN** the user opens Settings ▸ Advanced
- **THEN** the "Show layout flag at the cursor" toggle (with its BETA badge) SHALL appear at the top, followed by the "Remote Desktop mode (beta)" toggle when its beta flag is enabled, above the debug-logging toggle, path, and reveal button
- **AND** toggling either control SHALL persist and apply exactly as before

#### Scenario: Auto-fix tab no longer shows the experimental toggles
- **WHEN** the user opens Settings ▸ Auto-fix
- **THEN** the tab SHALL show only the master toggle and the unified exceptions list
- **AND** neither the caret-flag toggle nor the remote-desktop toggle SHALL appear on the Auto-fix tab

#### Scenario: Remote-desktop toggle stays gated
- **WHEN** the remote-desktop beta flag is not enabled
- **THEN** the Advanced tab SHALL NOT show the "Remote Desktop mode" toggle, while still showing the caret-flag and debug-logging controls


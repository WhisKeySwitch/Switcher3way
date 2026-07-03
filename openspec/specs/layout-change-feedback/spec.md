# Layout Change Feedback

## Purpose

Provides optional sensory feedback when the active keyboard layout changes: a floating flag badge displayed next to the text caret, and a short audio cue on the first keystroke after a switch. Both features are off by default and independently toggleable.

## Requirements

### Requirement: Show caret flag badge on layout change
When the caret flag feature is enabled and monitoring is active, the system SHALL display a floating badge with the flag of the newly active layout next to the text caret whenever the active layout changes. The badge SHALL only appear when the displayed flag actually differs from the previous one.

#### Scenario: Layout changes while typing in an editable field
- **WHEN** the active keyboard layout changes and the caret position can be determined
- **THEN** a flag badge for the new layout is displayed adjacent to the caret

#### Scenario: Feature disabled
- **WHEN** the caret flag setting is off
- **THEN** no badge is created or displayed on layout changes

### Requirement: Caret flag panel must not interfere with input
The caret flag badge SHALL be rendered in a non-activating, click-through panel that never steals keyboard focus from the frontmost application and ignores mouse events.

#### Scenario: Badge visible while user keeps typing
- **WHEN** the badge is on screen and the user continues typing or clicks
- **THEN** focus remains in the frontmost application and the badge is hidden on user input

### Requirement: Resolve caret position via Accessibility with fallbacks
The system SHALL obtain the caret rectangle through the Accessibility API, and SHALL fall back to text-marker-based resolution for Chromium/Electron applications, enabling their accessibility tree on demand. Accessibility queries SHALL be bounded by a short timeout to avoid stalling the app.

#### Scenario: Caret in a Chromium-based app
- **WHEN** the standard bounds-for-range attribute is unavailable in the focused element
- **THEN** the caret rectangle is resolved via the text-marker fallback path

#### Scenario: Degenerate caret geometry
- **WHEN** the resolved caret rectangle has invalid geometry (height below one point)
- **THEN** the badge is not shown

### Requirement: Suppress caret flag in sensitive contexts
The caret flag SHALL NOT be shown while secure input is active (password fields), while the frontmost application is a remote-desktop client, or over the app's own windows.

#### Scenario: Typing in a password field
- **WHEN** the layout changes while secure input is active
- **THEN** no caret badge is displayed

### Requirement: Play audio cue after layout change
When the key-sound feature is enabled, the system SHALL play a short sound on the first keystroke following a layout change, using a distinct sound depending on whether the current layout is the configured primary layout. The cue SHALL play at most once per layout change.

#### Scenario: First keystroke after a switch
- **WHEN** the layout has just changed and the user presses the first key
- **THEN** the layout-specific sound plays once and is not repeated on subsequent keystrokes

#### Scenario: Key sound disabled
- **WHEN** the key-sound setting is off
- **THEN** no sound is played after layout changes

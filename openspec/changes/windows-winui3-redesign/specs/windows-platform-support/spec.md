# Windows Platform Support — Delta

## MODIFIED Requirements

### Requirement: Present a tray-based status and control surface
The Windows build SHALL provide a system-tray presence whose flyout shows a live status header — the
foreground window's current layout and whether conversion is on or paused — and offers the core
controls: enable/disable, auto-fix toggle, remember-layout-per-app toggle, pause with selectable
durations, open Settings, open Help, and check for updates. The check-for-updates control SHALL show a
busy state while a check runs. Debug logging and opening the log folder SHALL NOT appear in the tray;
they live in the Settings window's Advanced section. The tray icon itself SHALL continue to indicate
the current layout and a dimmed/paused state.

#### Scenario: Show status and toggles in the tray
- **WHEN** the user opens the tray icon's flyout
- **THEN** the system SHALL display the current layout and enabled/paused state and provide controls to toggle conversion, toggle auto-fix, pause it for a chosen duration, and open Settings and Help

#### Scenario: Diagnostics controls are not in the tray
- **WHEN** the user opens the tray flyout
- **THEN** neither "Debug logging" nor "Open log folder" SHALL appear there — both are reached from Settings → Advanced

#### Scenario: Update check reflects progress
- **WHEN** an update check is running
- **THEN** the check-for-updates control SHALL show a busy/disabled state until it completes

### Requirement: Distribute as a signed, offline application
The Windows build SHALL be distributed through the Microsoft Store as a packaged application signed
by the Store, and MAY additionally be offered as a direct-download installer. It SHALL operate
entirely offline for detection, validation and conversion. A packaged build SHALL NOT update itself —
the Store services updates — and SHALL register "start with Windows" through its package startup task
rather than a startup-folder shortcut. A direct-download build MAY check for and install updates
itself, and SHALL state plainly what is missing if a runtime it depends on is absent, rather than
failing silently.

#### Scenario: Store distribution is signed without a developer certificate
- **WHEN** the app is submitted to the Microsoft Store
- **THEN** the Store SHALL sign the package, so installing it shows no "unknown publisher" warning

#### Scenario: Packaged builds defer updates to the Store
- **WHEN** an update check runs in a packaged build
- **THEN** the app SHALL NOT download or install an update itself, and SHALL indicate that updates come from the Store

#### Scenario: Start with Windows in a packaged build
- **WHEN** the user enables "start with Windows" in a packaged build
- **THEN** the app SHALL enable its package startup task, which stays visible in Windows' startup-apps settings

#### Scenario: A missing runtime is explained
- **WHEN** a direct-download build starts on a PC without the Windows App Runtime it depends on
- **THEN** the app SHALL name the required runtime instead of exiting with no message

#### Scenario: No runtime network dependency
- **WHEN** the application performs detection, validation, or conversion
- **THEN** it SHALL do so without any network access

## ADDED Requirements

### Requirement: Apply settings changes immediately
The Windows build SHALL commit each settings change to persistent storage at the moment the control
changes, without a separate Save or Cancel step. Surfaces that share the settings (tray flyout, status
card, Settings window) SHALL reflect a change made in any one of them without needing to be reopened.
Closing the Settings window SHALL NOT discard or defer any change.

#### Scenario: A toggled setting persists immediately
- **WHEN** the user flips a setting in the Settings window
- **THEN** the system SHALL write it to storage right away, and the change SHALL survive closing the window without any Save action

#### Scenario: Change reflected across surfaces
- **WHEN** the user toggles conversion or auto-fix from the tray flyout while the Settings window is open
- **THEN** the Settings window SHALL show the new value without being reopened, and vice versa

#### Scenario: Interface language applies in place
- **WHEN** the user changes the interface language in Settings
- **THEN** the open window SHALL re-render in the new language without an app restart

### Requirement: Give feedback on a successful conversion
The Windows build SHALL indicate a successful automatic conversion with a transient, non-focus-stealing
indicator shown near the corrected text that presents the original keystrokes and the converted word
and how to undo the fix. The indicator SHALL disappear on its own, SHALL NOT block or steal focus from
typing, and SHALL NOT post a persistent entry to the notification centre. A conversion that changes
nothing SHALL NOT show it.

#### Scenario: Success shows a transient indicator
- **WHEN** an automatic conversion successfully rewrites a word
- **THEN** the system SHALL briefly show, near the caret, the original and converted forms and an undo hint, then dismiss it automatically

#### Scenario: Undo hint follows the configured trigger
- **WHEN** the feedback indicator is shown
- **THEN** the undo hint SHALL name the currently configured trigger (for example the double-tap key when that is selected)

#### Scenario: No indicator when nothing changed
- **WHEN** detection results in no rewrite (kept, or already correct)
- **THEN** the system SHALL NOT show the conversion indicator

### Requirement: Surface errors and prompts as actionable notifications
The Windows build SHALL present the "cannot change text in this window" case as an actionable system
notification that persists in the notification centre and explains the likely elevation cause, replacing
the transient balloon tip. Where the product offers to remember a word after a fix, the notification
SHALL provide actions to undo the fix and to add the word to the never-convert list. The system SHALL
NOT raise a notification for each successful conversion.

#### Scenario: Protected-target error is actionable and persistent
- **WHEN** the foreground window cannot receive synthesized input because it runs at higher integrity
- **THEN** the system SHALL raise a persistent notification stating it cannot change text there and that the app may need to run as administrator

#### Scenario: Remember-word action updates the never-convert list
- **WHEN** the user chooses "Never convert this" on a conversion prompt
- **THEN** the system SHALL add that word to the never-convert list

#### Scenario: Success does not spam the notification centre
- **WHEN** conversions succeed normally
- **THEN** the system SHALL NOT post a notification-centre entry per fix

### Requirement: Guide first-run setup
On first launch the Windows build SHALL show a one-time setup flow that introduces what the app does,
lists the detected keyboard layouts with each language's dictionary readiness, and lets the user choose
the trigger key with a live preview that runs the real detector on what they type. The flow SHALL offer
to start the app with Windows, SHALL require no operating-system permission grants, and SHALL persist a
completion flag so it does not appear on subsequent launches.

#### Scenario: Onboarding appears once
- **WHEN** the app launches and first-run setup has not been completed
- **THEN** the system SHALL show the setup flow, and SHALL NOT show it again after it is completed

#### Scenario: Detected layouts and readiness are shown
- **WHEN** the user reaches the layouts step
- **THEN** the system SHALL list the installed layouts and, for each, whether its dictionary is available

#### Scenario: Trigger preview runs the real detector
- **WHEN** the user types a wrong-layout word in the trigger step's try-it field
- **THEN** the system SHALL show the conversion the real detector would produce

### Requirement: Manage exception apps visually
The Windows build SHALL let users add excluded applications by selecting from currently running
applications or by supplying an executable file, rather than typing an executable name. Each listed app
SHALL be shown with its icon and friendly name alongside its executable file name. Protected apps (the
built-in password managers) SHALL be shown as locked and SHALL NOT be removable. The never-convert and
always-convert word lists SHALL remain editable in place.

#### Scenario: Add an app from the running-apps picker
- **WHEN** the user opens the add-app picker
- **THEN** the system SHALL list currently running apps (excluding already-listed ones) and add the selected ones to the excluded list

#### Scenario: Protected apps cannot be removed
- **WHEN** the user views a protected password-manager entry
- **THEN** it SHALL be shown as locked with no remove action

#### Scenario: Apps show icon and friendly name
- **WHEN** the excluded-apps list is shown
- **THEN** each row SHALL display the app's icon and friendly name in addition to its executable file name

### Requirement: Render release notes and help as formatted content
The Windows build SHALL render update release notes as formatted text (headings and bullet points) and
SHALL NOT display raw markup. The Help window SHALL present a navigable table of contents derived from
the user guide's sections plus an in-app language switch, and SHALL open external links in the default
browser.

#### Scenario: Release notes render formatted
- **WHEN** an update is offered with release notes
- **THEN** the notes SHALL be shown as headings and bullets, not as raw markup characters

#### Scenario: Help has a working table of contents
- **WHEN** the user opens Help and selects a section
- **THEN** the corresponding section of the guide SHALL be shown, and the in-app language switch SHALL change the guide language without leaving the window

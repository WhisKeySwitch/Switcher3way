## ADDED Requirements

### Requirement: Ask for a Store review once, and only when earned
A build distributed through the Microsoft Store SHALL be able to ask the user to rate and review it, and
SHALL do so at most once unless the user invites a second ask. The request SHALL be made through the
platform's in-app rating facility so that the user does not leave the application, and SHALL be preceded
by the application's own prompt offering a permanent opt-out — the platform dialog carries no such
control, so without a preamble there is no click that means "never ask me again".

The ask SHALL be earned rather than scheduled. It SHALL become eligible only after the application has
demonstrably done its job for this user — a threshold of successful automatic conversions, spread over
several distinct days of use, on an installation that is not new — and those thresholds SHALL be
calibrated against recorded field use rather than chosen by taste. Conversions the user reversed SHALL
NOT count toward the threshold, and conversions the user performed with the manual trigger SHALL NOT
count as the application's own work.

The evidence the ask depends on SHALL be local counts only — no typed text, no per-event record, and
nothing transmitted anywhere — and SHALL hold the same line as the debug log, which does not record what
was typed.

No benefit, feature or behaviour SHALL be conditioned on rating the application, and the ask SHALL NOT
be routed by predicted sentiment: every user who reaches the threshold SHALL be offered the same dialog,
rather than the satisfied being sent to the store and the dissatisfied diverted to a private channel.

#### Scenario: The ask appears once the application has earned it
- **WHEN** a packaged build has successfully converted wrong-layout words for this user above the calibrated threshold, across the required number of distinct days, on an installation older than the required age
- **THEN** the application SHALL offer its own prompt asking whether the user would rate it, with three outcomes: rate, not now, and a permanent decline

#### Scenario: Only the explicit acceptance reaches the store
- **WHEN** the user chooses to rate from the application's own prompt
- **THEN** the platform's in-app rating dialog SHALL be shown, parented to that prompt
- **AND** if that dialog cannot be shown, the application SHALL open the store's review page for this product instead, through the launching facility a packaged application is permitted to use, never by starting another process

#### Scenario: A permanent decline is permanent
- **WHEN** the user declines permanently
- **THEN** the application SHALL never ask again, regardless of later versions, later usage, or elapsed time
- **AND** the recorded state SHALL be such that a value it does not recognise means "do not ask" rather than "ask again"

#### Scenario: Deferral costs one further ask, by invitation
- **WHEN** the user defers the ask
- **THEN** the application MAY ask once more, and only once, at a materially higher threshold and after a materially longer interval
- **AND** dismissing the prompt without choosing SHALL be read as a deferral, not as a permanent decline

#### Scenario: The ask never lands mid-sentence
- **WHEN** the threshold is crossed while the user is typing
- **THEN** the application SHALL NOT take focus at that moment; it SHALL hold the ask until the user has been idle, and if no such moment arrives it SHALL carry the pending ask into a later session rather than discard it or force it

#### Scenario: The application does not ask right after getting something wrong
- **WHEN** the application has recently failed to rewrite text, or the user has recently undone a conversion
- **THEN** the ask SHALL be suppressed until that is no longer recent, since asking for praise immediately after damaging a sentence is the worst available moment

#### Scenario: The ask is suppressed wherever interrupting would be wrong
- **WHEN** conversion is disabled or paused, first-run setup is unfinished, a password field has focus, the foreground application is one where conversion is suppressed, another of the application's own windows is open, or the settings file failed to load
- **THEN** the ask SHALL be suppressed

#### Scenario: Every decision not to ask is recorded with its reason
- **WHEN** the application evaluates whether to ask and decides not to
- **THEN** it SHALL log the reason by name, because a prompt that is correctly suppressed and a prompt whose code never ran are indistinguishable on screen
- **AND** the logging SHALL NOT repeat the same reason continuously while the condition persists

#### Scenario: A direct-download build does not ask
- **WHEN** the build is the unpackaged direct-download one
- **THEN** no ask SHALL be armed, shown, or offered, since such an installation has no store entitlement and the platform rating call cannot succeed for it

#### Scenario: The ask can be driven without waiting for the threshold
- **WHEN** the application is started with the diagnostic switch for the review prompt
- **THEN** it SHALL show the prompt immediately, bypassing every threshold, so the window, its translations and its outcomes can be verified without months of use
- **AND** a separate switch SHALL invoke the platform rating call directly and log its status, so that a failure of the call is distinguishable from the call never having been made

#### Scenario: The rating dialog is verified in the flavour that ships
- **WHEN** a release containing this feature is prepared
- **THEN** the platform rating dialog SHALL have been seen working in a store-installed build before that release is published, since a sideloaded package has no store licence and cannot exercise it

## MODIFIED Requirements

### Requirement: Present a tray-based status and control surface
The Windows build SHALL provide a system-tray presence whose flyout shows a live status header — the
foreground window's current layout and whether conversion is on or paused — and offers the core
controls: enable/disable, auto-fix toggle, remember-layout-per-app toggle, pause with selectable
durations, open Settings, open Help, and check for updates. In a packaged build it SHALL additionally
offer a way to rate the application, available at all times rather than only when the application
itself asks, so that a user who wants to leave a review need not wait for a prompt or be unable to
after declining one. The check-for-updates control SHALL show a busy state while a check runs. Debug
logging and opening the log folder SHALL NOT appear in the tray; they live in the Settings window's
Advanced section. The tray icon itself SHALL continue to indicate the current layout and a
dimmed/paused state.

#### Scenario: Show status and toggles in the tray
- **WHEN** the user opens the tray icon's flyout
- **THEN** the system SHALL display the current layout and enabled/paused state and provide controls to toggle conversion, toggle auto-fix, pause it for a chosen duration, and open Settings and Help

#### Scenario: Diagnostics controls are not in the tray
- **WHEN** the user opens the tray flyout
- **THEN** neither "Debug logging" nor "Open log folder" SHALL appear there — both are reached from Settings → Advanced

#### Scenario: Update check reflects progress
- **WHEN** an update check is running
- **THEN** the check-for-updates control SHALL show a busy/disabled state until it completes

#### Scenario: Rating is reachable without being asked
- **WHEN** the user opens the tray flyout of a packaged build
- **THEN** a control for rating the application SHALL be present, and choosing it SHALL take the same path as accepting the application's own ask

#### Scenario: Rating is absent from a direct-download build
- **WHEN** the user opens the tray flyout of an unpackaged build
- **THEN** no rating control SHALL be shown, rather than one that fails when used

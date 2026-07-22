## ADDED Requirements

### Requirement: Check the project's own releases for newer versions
The system SHALL determine whether a newer version exists by querying the project's public releases repository and comparing the latest published version against the running app's version, using numeric semantic-version comparison. The system SHALL NOT consult the upstream (rashn/RuSwitcher) project.

#### Scenario: Newer version published
- **WHEN** a check runs and the latest release version is numerically greater than the running `CFBundleShortVersionString`
- **THEN** the system SHALL treat an update as available and surface it to the user

#### Scenario: Up to date
- **WHEN** a check runs and the latest release version is equal to or lower than the running version
- **THEN** the system SHALL NOT prompt the user, and a manually initiated check SHALL report that the app is up to date

### Requirement: Automatic checks are scheduled and controllable
The system SHALL check for updates automatically after launch and at most daily thereafter, controlled by a persisted "check for updates automatically" setting that defaults to enabled. A background check failure (offline, rate-limited) SHALL be silent and logged, not surfaced as an alert.

#### Scenario: Automatic check disabled
- **WHEN** the user turns the automatic-check setting off
- **THEN** the system SHALL perform no background update checks until it is re-enabled, while the manual menu check remains functional

#### Scenario: Background failure stays quiet
- **WHEN** an automatic check fails due to network unavailability or an API error
- **THEN** the system SHALL log the failure and retry on the next scheduled check without alerting the user

### Requirement: Update prompt offers install, defer, and per-version skip
When an update is available the system SHALL present the new version and its release notes with three choices: install now, decide later, or skip this specific version. A skipped version SHALL not be offered again by background checks; a newer version or a manual check SHALL clear the skip.

#### Scenario: User skips a version
- **WHEN** the user chooses "Skip This Version" for version X and a later background check finds the latest release is still X
- **THEN** the system SHALL NOT prompt again for X

#### Scenario: Skip cleared by a newer release
- **WHEN** the user skipped version X and a background check finds version Y greater than X
- **THEN** the system SHALL prompt for Y

### Requirement: Downloads are verified before installation
The system SHALL verify the downloaded artifact before installing it: the DMG's SHA-256 SHALL match the checksum published with the release (manifest asset, with release-notes fallback for pre-manifest releases), and the new app bundle's code signature SHALL be valid and signed with the same certificate as the running app. If either verification fails the system SHALL abort the install, leave the current installation untouched, and inform the user.

#### Scenario: Checksum mismatch
- **WHEN** the downloaded DMG's SHA-256 does not match the published checksum
- **THEN** the system SHALL NOT install it and SHALL report the verification failure

#### Scenario: Foreign signing identity
- **WHEN** the bundle inside the DMG is unsigned or signed with a different certificate than the running app
- **THEN** the system SHALL NOT install it and SHALL report the verification failure

### Requirement: Install in place, preserve state, and relaunch
On a confirmed install the system SHALL replace the current app bundle with the verified new one, roll back to the previous bundle if replacement fails partway, and relaunch into the new version. The update SHALL NOT require the user to re-grant Accessibility or Input Monitoring (same signing identity), and SHALL NOT trigger a Gatekeeper first-launch block (no quarantine attribute on the installed bundle).

#### Scenario: Successful update
- **WHEN** the user confirms installation of a verified update
- **THEN** the system SHALL replace the installed bundle, relaunch the new version, and the new version SHALL run with the previously granted permissions intact

#### Scenario: Failed replacement rolls back
- **WHEN** replacing the bundle fails after the old bundle was moved aside
- **THEN** the system SHALL restore the old bundle and report the failure, leaving a working installation

### Requirement: Manual check from the status menu
The system SHALL provide a user-initiated update check that reports its outcome interactively — update available (with the standard prompt), up to date, or the error encountered — and ignores any previously skipped version.

#### Scenario: Manual check finds a skipped version
- **WHEN** the user invokes the manual check while the latest version is one they previously skipped
- **THEN** the system SHALL still present the update prompt for that version

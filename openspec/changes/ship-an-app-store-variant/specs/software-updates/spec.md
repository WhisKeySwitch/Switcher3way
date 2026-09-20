## ADDED Requirements

### Requirement: The App Store variant performs no self-update

The App Store variant SHALL contain no update check, no update download and no self-installation path. Updates for that variant SHALL be delivered solely by the platform's own app update mechanism.

This is not a configuration default that a user or a setting can re-enable: the update capability SHALL be absent from the build, because an App Store app that updates itself is rejected at review.

#### Scenario: No update check on launch

- **WHEN** the App Store variant launches
- **THEN** it SHALL make no request for release information and SHALL schedule no update check

#### Scenario: No update affordance in the interface

- **WHEN** a user opens the menu and the settings of the App Store variant
- **THEN** no "check for updates" command and no automatic-update preference SHALL be present

#### Scenario: The direct variant is unaffected

- **WHEN** the direct variant launches
- **THEN** it SHALL continue to check the project's own releases, offer, verify and install updates exactly as before

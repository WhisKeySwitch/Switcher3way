## MODIFIED Requirements

### Requirement: First-launch requirement for the unnotarized app is documented
The installation story SHALL be documented per distribution channel, and SHALL describe the channel as it actually is.

The direct DMG is signed with a Developer ID certificate, notarized, and stapled — on both the disk image and the application bundle, so that an application copied out of the image still launches without a network connection. Its documentation SHALL therefore NOT instruct users to right-click → **Open**, because that instruction is now false and teaches users to bypass a check that is passing.

Where a build is distributed without notarization — a pre-release, a locally built copy, or any bridge release that must carry an older signature — its notes SHALL state that first launch requires right-click → **Open**.

#### Scenario: First launch on another Mac
- **WHEN** a user opens a notarized release for the first time on a Mac other than the build machine
- **THEN** the application SHALL open by double-clicking, with no Gatekeeper bypass required, and the documentation SHALL NOT instruct them to right-click → **Open**

#### Scenario: An unnotarized build is distributed
- **WHEN** a build is published without notarization
- **THEN** its release notes SHALL state that the first launch requires right-click → **Open**

## ADDED Requirements

### Requirement: Two channels with distinct audiences and distinct contents

The project SHALL distribute through two channels: the Mac App Store, and a direct download. The two SHALL NOT be presented as interchangeable, because they do not provide identical protection — see `password-field-protection`.

Each channel's documentation SHALL make clear which variant a user is getting and how it differs.

#### Scenario: A user chooses a channel
- **WHEN** a prospective user reads the project's README or store listing
- **THEN** they SHALL be able to tell which variant each channel provides and what differs between them

#### Scenario: A release is published to the direct channel
- **WHEN** a direct release is published
- **THEN** it SHALL continue to carry its update manifest as a release asset and match the version recorded in `version.json`, unchanged by the existence of the App Store channel

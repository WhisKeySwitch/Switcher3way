# Delta: Distribution and Releases (publish-dmg-release)

## ADDED Requirements

### Requirement: Downloadable DMG is the primary install path
End users SHALL be able to install the app without a developer toolchain by downloading a drag-install DMG and dragging the app into Applications. The README Install section SHALL present this as the primary, first-listed path.

#### Scenario: Non-developer installs from the DMG
- **WHEN** a user without Xcode follows the README Install section
- **THEN** the first instructions SHALL be to download the DMG and drag `Switcher3way.app` into `/Applications`, with no build step required

### Requirement: A published release matches the current version
Each published release SHALL correspond to the version recorded in `version.json`, and its DMG SHALL contain an app bundle whose `CFBundleShortVersionString` equals that version. Stale artifacts from earlier version numbers SHALL NOT be presented as the current download.

#### Scenario: Release tag and bundle version agree
- **WHEN** a release is published for version `1.0.0`
- **THEN** the git tag SHALL be `v1.0.0` and the DMG's bundled app SHALL report `CFBundleShortVersionString` `1.0.0`

#### Scenario: Version bump requires a new release
- **WHEN** `version.json` is bumped to a new version
- **THEN** the previously published DMG SHALL NOT be the current advertised download until a new DMG and release are produced for the new version

### Requirement: First-launch requirement for the unnotarized app is documented
Because the distributed app is not notarized, the release notes and the README Install section SHALL state that the first launch on another Mac requires right-click → **Open** to bypass Gatekeeper.

#### Scenario: First launch on another Mac
- **WHEN** a user opens the downloaded app for the first time on a Mac other than the build machine
- **THEN** the documentation SHALL have told them to right-click the app and choose **Open** rather than double-clicking

### Requirement: Build-from-source remains a documented, correct secondary path
The README SHALL retain build-from-source instructions as a secondary path, and those instructions SHALL be executable as written: they SHALL include obtaining the source via `git clone`, SHALL use the directory name that cloning actually produces, SHALL note the required Swift/Xcode toolchain, and SHALL describe signing accurately (permissions persist across rebuilds only after the stable self-signed certificate is set up per `signing/README.md`; otherwise ad-hoc signing resets them each rebuild).

#### Scenario: Following build-from-source from a clean machine
- **WHEN** a developer copies the build-from-source commands verbatim onto a machine with the toolchain but no prior clone
- **THEN** the commands SHALL clone the repository, change into the directory that the clone created, build, and install without any missing or incorrect step

#### Scenario: Signing expectations are accurate
- **WHEN** a developer reads the signing note in the build-from-source section
- **THEN** it SHALL state that stable-cert signing (permissions surviving rebuilds) requires the self-signed certificate setup, and that without it the build signs ad-hoc and permissions reset per rebuild

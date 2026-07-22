## ADDED Requirements

### Requirement: Releases carry a machine-readable update manifest
Each published release in the public downloads repository SHALL attach the `version.json` update manifest as a release asset, recording the release's version and the SHA-256 of its DMG, so the in-app updater can discover the version and verify the artifact it downloads. The manifest's version SHALL equal the release tag's version and the bundled app's `CFBundleShortVersionString`.

#### Scenario: Publishing a release with the manifest
- **WHEN** a new version is released to the public downloads repository
- **THEN** the release SHALL include both the DMG and a `version.json` asset whose `version` matches the tag and whose `sha256` matches the uploaded DMG

#### Scenario: Updater consumes the manifest
- **WHEN** the in-app updater processes the latest release
- **THEN** it SHALL obtain the expected DMG checksum from the attached `version.json` asset (falling back to the checksum printed in the release notes only for releases published before manifests were introduced)

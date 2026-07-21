## MODIFIED Requirements

### Requirement: Observe keystrokes and buffer words globally
The Windows build SHALL observe keystrokes system-wide without requiring focus in the app, and SHALL buffer the current word and detect word boundaries so that finished words can be evaluated, mirroring the macOS keystroke buffer. The buffer SHALL retain punctuation and digit keys that produce letters in another installed layout as part of the token, and SHALL ignore the application's own synthesized keystrokes so a rewrite does not corrupt the buffer.

#### Scenario: Buffer a word up to a boundary
- **WHEN** the user types letters followed by a space or other word-boundary key in any foreground application
- **THEN** the system SHALL record the ordered keystrokes of the completed word and mark that a boundary occurred

#### Scenario: Reset the buffer on unsafe cursor movement
- **WHEN** the user moves the caret with arrows, clicks the mouse, or switches applications
- **THEN** the system SHALL discard the current keystroke buffer so a later rewrite cannot delete unrelated text

#### Scenario: Keep punctuation keys that are letters in another layout
- **WHEN** the user types a key that is punctuation in the current layout but a letter in another installed layout (for example the `,` key, which is `б` on a Ukrainian/Russian layout)
- **THEN** the system SHALL keep that key in the current word's buffer rather than treating it as a word boundary or reset

#### Scenario: Ignore the app's own synthesized input
- **WHEN** the application synthesizes keystrokes to rewrite text (backspaces and Unicode characters)
- **THEN** the system SHALL not let those synthesized events alter the keystroke buffer

### Requirement: Distribute as a signed, offline application
The Windows build SHALL be distributed as a code-signed installer and SHALL operate entirely offline at runtime. Both the executable and the installer SHALL be Authenticode-signed and timestamped so the signature outlives the certificate, and the signed executable SHALL launch on endpoint-protection-managed devices where an unsigned build is blocked.

#### Scenario: Signed, timestamped distribution
- **WHEN** the application is packaged for release
- **THEN** the executable and the installer SHALL both be Authenticode-signed and RFC-3161 timestamped

#### Scenario: Launches on a managed (EDR) device
- **WHEN** the signed application is launched on a device whose endpoint protection blocks unsigned or low-reputation executables
- **THEN** the signature SHALL establish the publisher so the executable is permitted to start

#### Scenario: No runtime network dependency
- **WHEN** the application performs detection, validation, or conversion
- **THEN** it SHALL do so without any network access

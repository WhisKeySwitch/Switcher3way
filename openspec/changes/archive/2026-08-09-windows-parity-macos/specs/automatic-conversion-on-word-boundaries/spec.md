## MODIFIED Requirements

### Requirement: Defer in remote or secure contexts
The system SHALL avoid automatic conversion when the active context is a secure input field, a control
detected as a password field by the focused-element password check, a protected password manager, or a
remote-desktop client that should defer to the remote host. The secure-context gate SHALL consult both
the process-global secure-input flag and the focused-element password check, because a field can be a
password field without the flag being set — an unmasked "show password" input, a web form that masks in
its own code, or a host that never requests secure event input. When conversion is suppressed for a
secure context, the phrase memory SHALL be reset, so that nothing typed into that field can influence a
later phrase correction.

#### Scenario: Avoid conversion in secure input
- **WHEN** the active input context is secure or protected
- **THEN** the system SHALL not perform automatic conversion

#### Scenario: Avoid conversion in an unmasked password field
- **WHEN** the focused control is reported as a password field by the focused-element check while the process-global secure-input flag is clear
- **THEN** the system SHALL not perform automatic conversion, SHALL reset the phrase memory, and SHALL record the suppression in the log

#### Scenario: Defer in remote desktop mode
- **WHEN** the app is running in remote-desktop mode and the frontmost client is a remote-desktop application
- **THEN** the system SHALL not perform automatic conversion on the local instance

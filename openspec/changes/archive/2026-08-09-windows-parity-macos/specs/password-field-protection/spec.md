## ADDED Requirements

### Requirement: Detect a focused password field beyond the secure-input flag
The system SHALL determine whether the currently focused control is a password field by inspecting the
focused Accessibility element, in addition to the process-global secure-input flag. A field SHALL be
treated as a password field when any of the following holds:

1. the focused element's Accessibility subrole is the secure-text-field subrole;
2. the focused element is a text-entry role whose title, description, placeholder value, or
   help text contains password wording;
3. the process-global secure-input flag is set (today's behavior, retained).

Any single positive signal SHALL be sufficient. The check SHALL deliberately over-block: a false
positive costs one unconverted word in a field labelled as a password, whereas a false negative
rewrites a credential.

#### Scenario: Masked password field in a browser
- **WHEN** the focused element is a masked password input in a browser or Electron application
- **THEN** the system SHALL report the focused control as a password field

#### Scenario: Password field revealed by a show/hide toggle
- **WHEN** the focused element is a text input that is not masked but whose accessible name, placeholder, or description contains password wording (for example "Password Hide password")
- **THEN** the system SHALL report the focused control as a password field, even though no masking and no secure-input flag is present

#### Scenario: Ordinary text field
- **WHEN** the focused element is a plain text field with no password wording and no masking
- **THEN** the system SHALL report the focused control as not a password field

### Requirement: Recognise password wording independently of the interface language
The password-wording match SHALL be case-insensitive and SHALL cover the languages a user of this app
is likely to encounter on a login form, independent of the app's own interface language, because the
label originates from the page or application being typed into and not from this app.

#### Scenario: Non-English login form
- **WHEN** the focused text field's accessible name is "Пароль", "Passwort", "Mot de passe", "Contraseña", "Senha", "Hasło", "密码", "パスワード", or "비밀번호"
- **THEN** the system SHALL report the focused control as a password field regardless of which interface language the app is running in

### Requirement: Suppress every text-touching path in a password field
When the focused control is reported as a password field, the system SHALL NOT perform automatic
conversion, SHALL NOT perform manual (trigger-invoked) conversion, and SHALL NOT display conversion
feedback. Phrase memory SHALL be reset so that no word typed into a password field can influence a
later correction.

#### Scenario: Word boundary reached inside a password field
- **WHEN** the user completes a word inside a password field and automatic conversion is enabled
- **THEN** the system SHALL leave the text unchanged, reset the phrase memory, and record the suppression in the log

#### Scenario: Manual trigger pressed inside a password field
- **WHEN** the user invokes the manual conversion trigger while a password field is focused
- **THEN** the system SHALL perform no conversion, no layout switch, and no candidate cycle

### Requirement: Detection must never block or crash the conversion path
The detection SHALL be best-effort and bounded. Any Accessibility query failure, timeout, or exception
SHALL be caught, SHALL be logged, and SHALL resolve to "not a password field" rather than propagating.
Queries SHALL be bounded by a short timeout so that an unresponsive application cannot stall
conversion, and the result SHALL be cached for the current focused element so that the check does not
repeat the full query on every keystroke.

#### Scenario: Accessibility query fails
- **WHEN** the Accessibility query for the focused element throws or returns nothing
- **THEN** the system SHALL log the failure, treat the field as not-a-password, and continue the conversion path without raising an error to the user

#### Scenario: Unresponsive application
- **WHEN** the focused application does not answer the Accessibility query within the bounded timeout
- **THEN** the system SHALL abandon the query, treat the field as not-a-password, and SHALL NOT block the conversion path for longer than the timeout

#### Scenario: Repeated checks on the same field
- **WHEN** consecutive words are evaluated while focus remains on the same element
- **THEN** the system SHALL reuse the cached verdict rather than re-running the full query, and SHALL invalidate the cache when focus changes

### Requirement: Report which signal produced the verdict
The system SHALL expose a diagnostic description naming each signal's individual result and the
focused element, so that a guard which never fires is distinguishable from a guard which correctly
finds nothing. This description SHALL be available both in the debug log and through a command-line
diagnostic mode of the application binary.

#### Scenario: Diagnosing the guard from the log
- **WHEN** debug logging is enabled and a word is evaluated
- **THEN** the log SHALL contain a line giving the overall verdict together with each signal's individual result and an identification of the focused element

#### Scenario: Diagnosing the guard interactively
- **WHEN** the user runs the application binary in its password-diagnostic mode
- **THEN** the system SHALL print the same per-signal breakdown for whatever control currently has focus

# Windows Platform Support — Delta (windows-mvp)

> **Reconciled 5 August 2026.** This change is the original Windows MVP; the WinUI 3 redesign
> (archived as `2026-08-05-windows-winui3-redesign`) shipped after it and superseded part of it.
>
> The distribution requirement that used to live here — Authenticode-signed exe *and* installer via
> SignPath, RFC-3161 timestamped, launching on EDR-managed devices — has been **removed from this
> delta**, because it no longer describes the product and syncing it would undo the accurate version.
> Distribution moved to the Microsoft Store, which signs the package itself; that is what makes the
> "unknown publisher" warning go away, and it is why the SignPath application was never pursued. The
> direct-download MSI is deliberately unsigned, with a SmartScreen click-through. The main spec's
> "Distribute as a signed, offline application" requirement already carries this, synced from the
> redesign — see decision 13 in the archived change.
>
> What remains below is the part of the MVP that shipped and that the main spec still understates.

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

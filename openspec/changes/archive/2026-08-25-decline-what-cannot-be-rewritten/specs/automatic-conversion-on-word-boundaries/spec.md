## ADDED Requirements

### Requirement: Do not attempt a replacement that cannot succeed
Automatic conversion replaces the completed word together with the boundary character that ended it, which means it must be able to reproduce that boundary. Where it cannot, the system SHALL decline the conversion rather than attempt it.

Attempting it is strictly worse than declining. The replacement cannot land, so the text is unchanged either way; what the failed attempt adds is a rewrite of the user's text, a verification failure, an undo, and an interruption — at the end of every line they type.

#### Scenario: A word ended by a key whose character cannot be re-typed
- **WHEN** a word is completed by a boundary that the replacement mechanism cannot reproduce — a line break or a tab, where the injection method used for text has no effect
- **THEN** the system SHALL leave the text and layout unchanged, SHALL record why in the diagnostic log, and SHALL NOT begin a replacement
- **AND** SHALL NOT raise a failure notification, because nothing failed — the app declined

#### Scenario: Reproducing the boundary as a keystroke is not a substitute
- **WHEN** a boundary character cannot be injected as text
- **THEN** the system SHALL NOT re-issue it as a key press in order to proceed, because the same key means different things in different targets — inserting a line break in an editor, and submitting in a message box where it has already been pressed once — and the two cannot be told apart before acting

#### Scenario: Ordinary word boundaries are unaffected
- **WHEN** a word is completed by a space
- **THEN** conversion SHALL proceed exactly as before

### Requirement: Report a failed replacement in terms of what failed
Where a replacement is attempted and does not succeed, any message shown to the user SHALL describe what actually happened. A message that names a cause the system has not established — in particular attributing an ordinary failure to the target running with elevated privileges — SHALL NOT be used as a general-purpose failure notice.

#### Scenario: A replacement that did not land is reported as such
- **WHEN** a replacement is written, checked, found not to match, and the original restored
- **THEN** the user SHALL be told that the conversion did not take effect and that their text was put back, rather than being told the window may be running as administrator

#### Scenario: A genuinely privileged target is still named as one
- **WHEN** the system's input is refused outright because the target runs at a higher integrity level
- **THEN** the message SHALL say so, since in that case it is both true and actionable

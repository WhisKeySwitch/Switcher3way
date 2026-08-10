## ADDED Requirements

### Requirement: Notify the user when a rewrite could not be applied
The system SHALL show a user-visible notification when a conversion's text replacement fails outright —
that is, when neither the retype path nor the clipboard fallback could apply the change — because the
user would otherwise experience the app silently doing nothing. The notification SHALL be throttled so
that a repeatedly failing context cannot produce a stream of notifications.

#### Scenario: Replacement fails in a window that rejects synthetic input
- **WHEN** a conversion's text replacement fails and no fallback path succeeds
- **THEN** the system SHALL show a notification explaining that it could not act in this window

#### Scenario: Repeated failures in the same context
- **WHEN** further replacements fail within the throttle interval of a notification already shown
- **THEN** the system SHALL suppress the additional notifications and record them in the log instead

#### Scenario: Successful conversion
- **WHEN** a conversion completes successfully
- **THEN** the system SHALL NOT show any notification — success is communicated by the caret feedback and the status icon only

### Requirement: Offer to remember a word after an undo without blocking input
When the user reverses a conversion with the manual trigger shortly after it was applied, the system
SHALL offer to add that word to the never-convert list. The offer SHALL be delivered as a non-blocking
notification carrying an action button, and SHALL NOT be a modal dialog: it appears mid-typing, so it
MUST NOT take keyboard focus or interrupt the user's input.

#### Scenario: User undoes a conversion
- **WHEN** the user reverses a conversion with the manual trigger within the offer window and no typing intervened
- **THEN** the system SHALL post a notification naming the word and offering an action that adds it to the never-convert list, without taking focus from the frontmost application

#### Scenario: User accepts the offer
- **WHEN** the user activates the notification's never-convert action
- **THEN** the system SHALL append the converted form of the word to the never-convert list, persist it, and reflect it in the exceptions list

#### Scenario: User ignores the offer
- **WHEN** the user does not act on the notification
- **THEN** the system SHALL leave the exception lists unchanged and SHALL continue converting normally

### Requirement: Ask about a given word at most once per session
The system SHALL offer to remember a given word at most once per application session, and SHALL NOT
offer a word that is already present in the never-convert list.

#### Scenario: Same word undone twice
- **WHEN** the user undoes a conversion of a word that has already been offered in this session
- **THEN** the system SHALL NOT post a second offer for that word

#### Scenario: Word already excepted
- **WHEN** the word is already in the never-convert list
- **THEN** the system SHALL NOT post an offer for it

### Requirement: Degrade safely when notifications are unavailable
Notification delivery SHALL be optional to the app's function. The system SHALL request notification
authorization lazily, and SHALL treat a denial, a registration failure, or a delivery failure as a
logged condition only — never as an error surfaced to the user and never as a reason to abort or skip a
conversion. Registration and delivery failures SHALL be logged regardless of the debug-log setting,
because otherwise the user experiences only silence.

#### Scenario: User has denied notification permission
- **WHEN** notification authorization has been denied and a notifiable event occurs
- **THEN** the system SHALL log the event and continue operating normally, with conversion unaffected

#### Scenario: Notification registration fails at launch
- **WHEN** notification registration fails during startup
- **THEN** the system SHALL record the reason in the log unconditionally and SHALL continue to start the menu-bar item and monitoring

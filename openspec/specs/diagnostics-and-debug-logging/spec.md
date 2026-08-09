# Diagnostics and Debug Logging

## Purpose

Provides an opt-in file log for troubleshooting: conversion decisions, permission state, and internal events are written to a rotating log file that the user can enable and reveal from the Advanced settings tab.
## Requirements
### Requirement: Gate logging behind an opt-in setting
The system SHALL write log messages to a file only when the debug-log setting is enabled; when it is disabled (the default), no log file is written.

#### Scenario: Debug log disabled
- **WHEN** the debug-log setting is off and a loggable event occurs
- **THEN** nothing is written to disk

#### Scenario: Debug log enabled
- **WHEN** the debug-log setting is on and a loggable event occurs
- **THEN** the event is appended to the log file in the user's Logs directory

### Requirement: Bound log file size
The system SHALL cap the log file's size by truncating it when it exceeds 5 MB, so that logging never grows without bound.

#### Scenario: Log exceeds the size cap
- **WHEN** the log file grows past 5 MB
- **THEN** it is truncated before further messages are appended

### Requirement: Expose log controls in Advanced settings
The Advanced settings tab SHALL provide a toggle for the debug log, display the log file's path, and provide a button that reveals the log file in Finder.

#### Scenario: User reveals the log
- **WHEN** the user clicks the show-log button and the log file exists
- **THEN** the file is revealed in Finder

#### Scenario: No log file yet
- **WHEN** the user clicks the show-log button but no log file exists
- **THEN** the user is informed instead of Finder opening

### Requirement: Always-on channel for critical failures
The system SHALL provide a logging channel that writes regardless of the debug-log setting, reserved
for failures the user could otherwise never report: the Accessibility API becoming unavailable,
notification registration failing, or a subsystem the app depends on refusing to start. Ordinary
operational messages SHALL continue to be gated behind the opt-in debug-log setting.

#### Scenario: A subsystem fails to start with debug logging off
- **WHEN** notification registration or the Accessibility connection fails while the debug-log setting is off
- **THEN** the system SHALL still append a line recording the failure and its reason to the log file

#### Scenario: Ordinary events with debug logging off
- **WHEN** a routine conversion decision is made while the debug-log setting is off
- **THEN** nothing SHALL be written to disk

### Requirement: Record the password-guard verdict per evaluated word
When debug logging is enabled, the system SHALL log the password-guard verdict together with each
signal's individual result for every word it evaluates — not only when the guard fires. A guard that is
broken and a guard that correctly finds nothing produce identical output otherwise, which is how the
equivalent Windows guard went unnoticed as inoperative for four releases.

#### Scenario: Word evaluated in an ordinary field
- **WHEN** debug logging is on and a word is evaluated in a field that is not a password field
- **THEN** the log SHALL contain a line giving the negative verdict and each signal's individual result

#### Scenario: Word evaluated in a password field
- **WHEN** debug logging is on and a word is evaluated while a password field is focused
- **THEN** the log SHALL contain both the guard line and an explicit line stating that conversion was suppressed because of a password field

### Requirement: Never record typed characters before the password guard has run
The system SHALL NOT write the identity of individual keystrokes to the log. Word-level text MAY be
logged only at the point where the password guard has already been consulted and has reported the
field as not a password. Enabling the debug log SHALL NOT be a way to capture what the user typed into
a credential field.

#### Scenario: Keystrokes buffered with debug logging on
- **WHEN** debug logging is on and the user types characters into any field
- **THEN** the log MAY record that a keystroke was buffered and the resulting buffer length, but SHALL NOT record which key it was

#### Scenario: Word text in the decision line
- **WHEN** debug logging is on and a word is evaluated in a field the password guard reports as not a password
- **THEN** the decision line MAY include the rendered candidate words, since that path is unreachable for a password field


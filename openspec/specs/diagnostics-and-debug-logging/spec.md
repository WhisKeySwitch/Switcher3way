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

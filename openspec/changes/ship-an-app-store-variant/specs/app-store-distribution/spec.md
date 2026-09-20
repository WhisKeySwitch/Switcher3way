## Purpose

Defines the sandboxed App Store variant of Switcher3way: which behaviours it keeps, which it loses because the App Sandbox forbids them, and what must be demonstrably true before it is submitted for review.

## ADDED Requirements

### Requirement: Two build flavours from one source

The project SHALL produce two variants from identical sources, distinguished at build time: a **direct** variant (unsandboxed, Developer ID signed, notarized, distributed as a DMG) and an **App Store** variant (sandboxed, distributed through the Mac App Store). The variants SHALL carry distinct bundle identifiers so that both can be installed and run on the same machine simultaneously.

Detection quality SHALL NOT differ between variants: the resolver, typo guard, short-word lists and phrase tracking SHALL be the same code producing the same verdicts, so that a conversion decision correct in one variant is correct in the other.

#### Scenario: Both variants installed together

- **WHEN** both variants are installed on one Mac
- **THEN** each SHALL run under its own bundle identifier with its own permission grants and its own settings, and neither SHALL replace or interfere with the other

#### Scenario: Identical detection outcome

- **WHEN** the same word is typed with the same layout state under each variant
- **THEN** both SHALL reach the same conversion decision

### Requirement: The App Store variant runs sandboxed and converts text

The App Store variant SHALL declare the App Sandbox entitlement and SHALL retain the functions the sandbox permits: keystroke monitoring, synthesizing keystrokes to retype text, switching the keyboard layout, reading the frontmost application's identity, and reading the pasteboard.

#### Scenario: End-to-end conversion under the sandbox

- **WHEN** a user types a word in the wrong layout and invokes the manual trigger in the sandboxed variant, with Accessibility and Input Monitoring granted
- **THEN** the system SHALL replace the typed text with the converted text and switch the keyboard layout

### Requirement: Capabilities lost to the sandbox are identified and degraded deliberately

Inspection of another application's Accessibility elements is unavailable under the App Sandbox. Every behaviour that depends on it SHALL either degrade to a stated fallback or be absent in the App Store variant, and SHALL NOT fail in a way that misrepresents itself as working.

The affected behaviours are: focused-element inspection for password detection (see `password-field-protection`), caret position resolution for conversion feedback, selection-based conversion, and reading back what a rewrite actually landed.

#### Scenario: Caret position cannot be resolved

- **WHEN** the App Store variant needs to position conversion feedback and no caret position is available
- **THEN** it SHALL fall back to the window anchor rather than suppressing the feedback or reporting an error

#### Scenario: A lost capability is not silently claimed

- **WHEN** the App Store variant cannot perform an Accessibility-dependent check
- **THEN** the diagnostic output SHALL state that the signal is unavailable in this variant, distinguishably from the signal being available and returning a negative result

### Requirement: Submission readiness is demonstrated, not assumed

Before submission, the App Store variant SHALL be verified on a build produced by the App Store flavour of the build script — not on the direct build, and not on a locally-modified copy. The verification SHALL cover: conversion end to end, the password-field guard, the absence of any self-update path, and purchase and restore.

#### Scenario: Verifying in the flavour that ships

- **WHEN** a behaviour is claimed to work in the App Store variant
- **THEN** the evidence SHALL come from running the sandboxed, App-Store-flavour build, because the sandbox changes which system APIs answer

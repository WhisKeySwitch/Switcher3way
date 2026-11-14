# Spec Delta

## Purpose

Lets the App Store build ask satisfied users for an App Store rating, through the only mechanism Apple permits, at a moment that never interrupts the typing the app exists to protect.

## ADDED Requirements

### Requirement: Ask only through the system review API, and only in the App Store build
The App Store build SHALL request a rating only through the system's review API, and SHALL NOT show any rating prompt, dialog or rating control of its own. The direct build SHALL NOT request a rating at all. Because the system decides whether a request is shown and does not report the outcome, the system SHALL NOT assume that a request produced a prompt.

#### Scenario: Direct build never asks
- **WHEN** the direct build meets every other condition in this capability
- **THEN** it SHALL NOT request a rating

#### Scenario: No custom prompt
- **WHEN** the App Store build decides to ask
- **THEN** the only thing it SHALL do is call the system review API; it SHALL NOT show its own star rating, dialog or pre-prompt

### Requirement: Ask only after the app has proved useful
The App Store build SHALL request a rating only when all of the following hold: the user has kept at least a threshold number of automatic conversions, where a conversion counts as kept when its undo window closes without the user undoing it; at least a minimum number of days have passed since the app was first launched; and the current entitlement allows conversion. The threshold and the minimum number of days SHALL be named constants, recorded with the reasoning that chose them.

#### Scenario: Not enough kept conversions yet
- **WHEN** the user has kept fewer conversions than the threshold
- **THEN** the system SHALL NOT request a rating

#### Scenario: An undone conversion does not count
- **WHEN** the user undoes an automatic conversion within its undo window
- **THEN** that conversion SHALL NOT count toward the threshold

#### Scenario: A locked-out user is never asked
- **WHEN** the trial has ended and nothing is purchased
- **THEN** the system SHALL NOT request a rating, however many conversions were kept before

### Requirement: Ask only while the user has the app in front
The system SHALL request a rating only while one of its own windows is frontmost because the user opened it, namely when the Settings window opens. It SHALL NOT request a rating while the user is typing in another application, SHALL NOT activate itself in order to ask, and SHALL NOT ask while the status menu is open, while the setup checklist or purchase window is showing, or in the moment right after a conversion.

#### Scenario: Asking when Settings opens
- **WHEN** the user opens Settings and every eligibility condition holds
- **THEN** the system SHALL request a rating attached to the Settings window, shortly after it appears

#### Scenario: Never mid-typing
- **WHEN** the eligibility conditions become true as a result of a conversion the user just kept
- **THEN** the system SHALL NOT request a rating then, and SHALL wait until the user next opens Settings

#### Scenario: Not over another app window
- **WHEN** the setup checklist or the purchase window is showing
- **THEN** the system SHALL NOT request a rating

### Requirement: Ask rarely
The system SHALL request a rating at most once per app version, and SHALL NOT request one within 120 days of its previous request, regardless of what the system's own limit would allow.

#### Scenario: Once per version
- **WHEN** the system has already requested a rating in the current app version
- **THEN** it SHALL NOT request another until the version changes

#### Scenario: Minimum gap between versions
- **WHEN** a new app version is installed less than 120 days after the last request
- **THEN** the system SHALL NOT request a rating until 120 days have passed

### Requirement: The user can always choose to rate
The App Store build SHALL offer a menu item that opens the app's App Store listing on its review page, available at all times and independent of the automatic request's conditions and limits.

#### Scenario: Rating from the menu
- **WHEN** the user chooses the rate item in the status menu
- **THEN** the system SHALL open the App Store on the app's review page

### Requirement: Decisions are logged and hold no typed text
Each time the system evaluates whether to request a rating, it SHALL record the outcome and the reason in the debug log, including the decision not to ask and which condition was unmet. The values it keeps to decide SHALL be counts and dates only, never any text the user typed.

#### Scenario: A decision not to ask is explained
- **WHEN** the user opens Settings and the system does not request a rating
- **THEN** the debug log SHALL record which condition was unmet, for example the kept-conversion count against the threshold

#### Scenario: No text is stored
- **WHEN** the review counters are inspected
- **THEN** they SHALL contain only numbers, dates and a version string

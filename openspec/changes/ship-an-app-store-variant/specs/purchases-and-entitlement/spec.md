## Purpose

Defines how the App Store variant is paid for and what the app does before, during and after a purchase: the free trial, the two purchase options, and how the app behaves when entitlement is absent or lapses.

## ADDED Requirements

### Requirement: Free trial, then two ways to pay

The App Store variant SHALL be downloadable at no charge and SHALL offer a time-limited introductory trial with the full feature set. After the trial the user SHALL be able to continue by either an auto-renewing subscription or a one-time purchase that does not expire.

Purchase, trial eligibility and renewal SHALL be handled by the platform's in-app purchase system. The app SHALL NOT implement its own trial clock, licence file or activation server in this variant.

#### Scenario: First launch

- **WHEN** the App Store variant is launched for the first time
- **THEN** the full feature set SHALL be available for the trial period without the user being asked to pay or sign in

#### Scenario: One-time purchase never expires

- **WHEN** a user has completed the one-time purchase
- **THEN** the app SHALL remain fully functional indefinitely, with no renewal and no further payment

### Requirement: Entitlement survives reinstall and other Macs

The app SHALL determine entitlement from the platform's purchase records rather than from local state alone, so that a user who reinstalls the app, or installs it on another Mac signed in to the same account, regains their purchase without contacting support. A user-invokable restore SHALL be available.

#### Scenario: New Mac, same account

- **WHEN** a user who has purchased installs the app on a second Mac under the same account
- **THEN** the app SHALL recognise the entitlement without a new purchase

#### Scenario: Restore after reinstall

- **WHEN** a user reinstalls and the app does not immediately see the purchase
- **THEN** a restore action SHALL be available and SHALL re-establish entitlement

### Requirement: An unpaid app stops converting visibly, never silently

When the trial has ended and no purchase is active, the app SHALL stop performing automatic conversion and SHALL make that state visible in the menu-bar status, because this app's normal successful state is indistinguishable from doing nothing. It SHALL NOT simply cease to act.

The app SHALL NOT withhold anything the user has already typed, SHALL NOT interfere with their input, and SHALL remain closable and uninstallable without payment.

#### Scenario: Trial expires while the app is running

- **WHEN** the trial period ends
- **THEN** the app SHALL stop converting, SHALL show an unambiguous unpaid state in its status item, and SHALL offer the purchase options

#### Scenario: Expired state is not mistaken for a malfunction

- **WHEN** a user types a wrong-layout word after the trial has ended
- **THEN** the reason the word was left alone SHALL be discoverable from the app's own interface, not only from its logs

### Requirement: Purchase state is never reported dishonestly

The app SHALL NOT claim an entitlement it cannot verify, and SHALL NOT deny one the platform reports as valid. When the entitlement cannot be determined — no network on first launch, a pending transaction, a platform error — the app SHALL resolve in the user's favour for the duration of that session and retry, rather than locking out a paying user.

#### Scenario: Entitlement cannot be checked

- **WHEN** the purchase state cannot be determined at launch
- **THEN** the app SHALL continue working for that session, SHALL log the reason, and SHALL re-check rather than treating the user as unpaid

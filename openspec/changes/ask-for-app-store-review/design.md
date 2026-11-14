# Design

## Context

See proposal.md for why. The facts the design rests on:

- **The system review API** is StoreKit's `AppStore.requestReview(in:)`, which takes an
  `NSViewController` on macOS 13 and later; the App Store build requires macOS 27. The system
  decides whether to show anything, caps it at three prompts per 365 days, and returns nothing. In a
  development build it always shows, and in TestFlight it never does. Only a build installed from the
  App Store shows the real behaviour.
- **The app is a menu-bar utility** (`LSUIElement`). It is frontmost only when the user opens one of
  its windows. The status menu runs its own tracking loop, and a sheet presented under it would either
  not appear or break the menu.
- **"Kept" is already observable.** `AppDelegate.lastAutoConverted` records each automatic
  conversion, and the learn-from-undo path treats a trigger press within 8 seconds as an undo. A
  conversion whose 8-second window passes untouched is one the user accepted.
- **The field log** (`switcher3w.log`, 2026-09-09..24, one heavy user) has 147 automatic conversions
  over 12 active days: 7 to 16 a day, about 12 on average.

## Goals / Non-Goals

**Goals:**

- The request can never land while the user is typing into another app.
- The eligibility rule is a pure function with an injected clock, and is unit-tested.
- A user who wants to rate can do it at any time, without waiting for the rule.

**Non-Goals:**

- Measuring whether a prompt was shown or what rating was given. The API does not say, and guessing
  would make the log lie.
- A review request in the direct build, or a "star us on GitHub" equivalent there.
- Tuning the thresholds from store data. There is none yet; see the risks.

## Decisions

### 1. The rule lives in the core as `ReviewPromptPolicy`

A Foundation-only value type in `Switcher3wCore`: inputs are kept-conversion count, first-launch
date, whether the entitlement allows conversion, the current version, the version last asked in, the
date last asked, and now. The output is either *ask* or *not yet*, with the unmet condition named.
The app target cannot be unit-tested, and the core already holds every rule that decides whether to
act on the user's behalf.

*Alternative considered:* the rule inline in `AppDelegate`. Rejected. It is small enough to hide a
mistake nobody sees for 120 days, which is exactly when it would matter.

### 2. The thresholds

- **30 kept conversions.** About three active days for the one user in the field log. A lighter user
  reaches it later, and that is the intent: the request should come after the app has fixed enough
  words to be noticed.
- **7 days since first launch.** So a burst of conversions on day one, while someone is testing the
  app, does not trigger it. It also lands inside the 14-day trial, when the user is deciding whether
  to pay, which is when a good experience is freshest.
- **Once per version, and no sooner than 120 days after the last request.** Stricter than the
  system's cap of three a year, because the app has only one moment to ask in and should not spend it
  on someone who already declined.

These are judgement, informed by one user's log; the constants carry that note. They are the first
thing to revisit once the listing has real reviews.

### 3. The moment: Settings opening, with a delay

The coordinator runs when the Settings window becomes key. After about 1.5 seconds, so the window is
settled and the user has seen it, it asks the policy and, on *ask*, calls
`AppStore.requestReview(in:)` with the Settings view controller. It records the version and date at
that point, whether or not the system shows anything.

It does not run when the setup checklist or the purchase window is visible. It never runs from the
conversion path. When a kept conversion crosses the threshold, it only updates the counter.

*Alternatives considered:*
- *On the Nth kept conversion.* Rejected. That moment is by definition mid-typing.
- *When the menu opens.* Rejected, because of menu tracking.
- *On closing Settings.* Rejected. The app deactivates as the window closes, and the request would
  either vanish or pull the app back in front.

### 4. Counting kept conversions

At each automatic conversion the app already sets `lastAutoConverted`. A one-shot timer 8 seconds
later checks whether that same record is still in place: an undo clears it, and so does a newer
conversion. If it is still there, the kept counter goes up by one. If a newer conversion replaced it,
that newer conversion's own timer does the counting. So each conversion is counted at most once, and
never if it was undone.

### 5. The menu item

"Rate Switcher3Way on the App Store…" appears in the App Store build's menu, next to the purchase
item. It opens `macappstore://apps.apple.com/app/id<APP_ID>?action=write-review`, where
`<APP_ID>` is the listing's numeric Apple ID as a constant. It is always available and does not
count as a request.

### 6. Storage and logging

Keys are `com.switcher3w.review.keptConversions`, `.firstLaunch`, `.lastAskedVersion` and
`.lastAskedAt`, in the App Store build's container. Every evaluation logs one `review:` line through
`rslog`, for example `review: not yet — 12/30 kept conversions` or
`review: requested (version 1.8.0)`.

## Risks / Trade-offs

- [A user who never opens Settings is never asked] → Accepted. The menu item covers anyone who wants
  to rate. A prompt that could land mid-typing would cost more than the missing rating.
- [Opening Settings to change something, then getting a rating sheet, is mildly annoying] → Delay of
  1.5 s, once per version at most, and never within 120 days. The system may also decline to show it.
- [Thresholds rest on one heavy user's log] → Named constants with that note, and a revisit once there
  are real reviews.
- [The API cannot be verified outside a store-installed build] → Development builds show the prompt
  every time. The test plan checks the policy by unit test and the moment by a development build; the
  real behaviour is checked once after release.
- [Guideline 5.6.1 changes or is read strictly] → The design uses only the system API, and the menu
  item links to the review page, which Apple documents as permitted.

## Migration Plan

- New keys only. On first run after the update, the first-launch date is set to now, so users who
  have had the app for months get their 7 days again. That errs toward asking later.
- Rolling back is a revert. The keys are left behind unused.

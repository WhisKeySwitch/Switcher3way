## Why

The Store listing (product `9MXFXL7GG3C5`) has been live since August 2026 and the app has never once
asked anyone to rate it. Store search ranking and the listing's own credibility both weigh rating
volume, and a new user deciding whether to grant a global keyboard hook to an unknown publisher reads
the review count before anything else. So the reviews matter more for this app than for most.

The reason there are so few is structural, not accidental: **the app succeeds by being unnoticeable.**
It lives in the tray, has no main window, and shows nothing on success. `Toast.cs` states the policy in
its own header — "a layout fixer that toasts on success would be unusable" — and that is correct. But
it means the app has removed every moment at which a user would naturally think about it, which is
exactly the moment a review gets written.

This change therefore proposes the first interruption the app would ever make **for its own benefit
rather than the user's**, and that is the whole risk. A nag in a keyboard utility is uninstall-grade
annoyance, and it would arrive mid-sentence by construction, because mid-sentence is when the app is
in use. So the ask is bound hard: once in the lifetime of the install, only after the app has provably
earned it, never at a moment when it has just got something wrong, and retireable forever in one click.

There is **no measurement behind the thresholds yet**, and this proposal does not pretend otherwise.
The twelve-day field log behind 1.6.0 counted 5,731 auto *decisions*, but the overwhelming majority of
decisions are keeps — the app's most common action is to do nothing — so it says nothing about how many
*conversions* a real user sees in a week. Task 1 is to extract that number from the log before any
threshold ships, and the thresholds below are placeholders until it does.

## What Changes

- **Count what the app has actually done, locally.** Three new persisted settings: lifetime successful
  conversions, the date of first run, and the number of distinct days on which a conversion happened.
  Counts only — never the words, never a timestamp per conversion, never transmitted. The debug log
  already refuses to record which key was pressed; this holds the same line.
- **Ask once, on an earned milestone, in the Store build only.** Placeholder: ≥100 successful
  conversions across ≥3 distinct active days, with the install at least 7 days old. Calibrated in task 1
  against the field log so that the ask lands at roughly a week or two of real use rather than on day
  one or never.
- **The ask is the app's own window, not the Store's.** A small prompt in the shape of
  `UpdatePromptWindow` — "Enjoying Switcher3way?" / **Rate it** · **Not now** · *No thanks*. Only
  **Rate it** calls `StoreContext.RequestRateAndReviewAppAsync`, Microsoft's in-app review dialog, so
  the user never leaves the app and the Store dialog is never spent on somebody who was going to say no.
- **"Not now" re-arms once at a higher threshold; "No thanks" retires the feature permanently.** Two
  asks in the lifetime of an install, maximum, and only if the user invited the second one.
- **Nine conditions suppress the ask**, every one of them logged by name. Not while paused or disabled;
  not before onboarding is finished; not while a password field has focus or a denied app is in the
  foreground; not when the settings file failed to load; and **not within an hour of a failed rewrite or
  an undo** — asking for five stars immediately after mangling someone's sentence is the worst version
  of this feature.
- **A permanent "Rate Switcher3way" entry** in the tray flyout and the Settings About tab, so a user
  who wants to review the app can, without waiting for a milestone or after dismissing the ask.
- **Nothing at all in the MSI build.** An MSI user has no Store entitlement, `StoreContext` has no
  package identity to work from, and the call would fail; the milestone, the window and the menu row are
  all gated on `PackageInfo.IsPackaged`.
- **Every decision not to ask is logged with its reason**, which is the point rather than a nicety. A
  prompt that is correctly suppressed and a prompt whose code never ran leave identical evidence —
  nothing on screen — and this app has already lost one test session to exactly that ambiguity.

## What this does not do

- **No reward for reviewing.** Nothing is unlocked, enabled or extended by rating, which Store policy
  forbids and which would corrupt the ratings anyway.
- **No sentiment fork.** The ask does not screen for happy users by asking "are you enjoying it?" and
  routing the unhappy ones to a private feedback form instead of the Store. It is a well-known pattern
  and it is rating manipulation; the same dialog goes to everyone who reaches the milestone.
- **No telemetry.** The counters exist to time one local decision and never leave the machine. Nothing
  here adds a network call — the app's "no network for detection" guarantee is untouched, and the only
  network traffic remains the MSI build's update check.
- **No second ask per version.** This is not a per-release prompt; shipping 0.7.0 does not re-arm
  anything.

## Capabilities

### New Capabilities

None. The ask is Windows-shell behaviour and belongs with the rest of it.

### Modified Capabilities

- `windows-platform-support`: adds a requirement for asking for a Store review on earned usage — when it
  may be shown, the conditions that suppress it, the once-ever cap and permanent opt-out, the local-only
  counters, and the manual entry point. Extends the tray-surface requirement with the manual row.

## Impact

- **New:** `StoreReview.cs` (milestone evaluation, suppression reasons, the Store call),
  `RateWindow.xaml` + `.xaml.cs` (the in-app ask).
- **Modified:** `SettingsManager` (three counters plus the ask state: asked, re-armed, retired),
  `Tray` (subscribe to `Engine.Converted` for the count, to `Engine.Undone`/`Engine.Notify` for the
  cool-off, host the milestone check and the new menu row), `TrayFlyoutWindow` and `SettingsWindow`
  (the manual row), `Loc.cs` (new strings across all 16 interface languages),
  `Switcher3way.Core.Tests` or a new App-level test for the milestone predicate.
- **Dependencies:** none added. `Windows.Services.Store` comes with the
  `net8.0-windows10.0.19041.0` target framework; `RequestRateAndReviewAppAsync` requires build 17763,
  which is already `TargetPlatformMinVersion`.
- **Testing is the hard part.** The Store review dialog does not work in a sideloaded package — it
  needs a Store-installed app with a licence — so the one surface that cannot be verified locally is the
  one the user will see. This repo's rule is "verify in the flavour that ships", and honouring it here
  means a Store package flight before release, not a sideload. See `design.md`.
- **Store submission:** no new capability, no manifest change, so no new review surface. The runFullTrust
  justification is unaffected.

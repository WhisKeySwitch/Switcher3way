# Tasks

## 1. The rule

- [ ] 1.1 Add `ReviewPromptPolicy` to `Switcher3wCore`, with named constants for 30 kept conversions, 7 days and 120 days, each documented with its reasoning. Verify: the core builds on its own with `swift build --target Switcher3wCore`.
- [ ] 1.2 Unit-test it with an injected clock: too few kept conversions, too few days, entitlement expired, already asked this version, a new version within 120 days, a new version after 120 days, and the all-conditions-met case. Each "not yet" must name its unmet condition. Verify: `swift test --filter ReviewPromptPolicyTests` passes.

## 2. Counting

- [ ] 2.1 Add the four `com.switcher3w.review.*` keys to `SettingsManager`, with the first-launch date set on first read. Verify: a fresh defaults domain reads count 0 and a first-launch date of now, and the values survive a relaunch.
- [ ] 2.2 In the App Store build only, start a one-shot 8-second timer at each automatic conversion, and increment the kept count only if that conversion's record is still in place when it fires. Verify: in a development build with debug logging on, a kept conversion logs one increment, and an undone one logs none.

## 3. Asking

- [ ] 3.1 Add a review coordinator, compiled into the App Store flavour only, that runs 1.5 s after the Settings window becomes key. It skips when the checklist or purchase window is visible, asks the policy, calls `AppStore.requestReview(in:)` with the Settings view controller on *ask*, and records version and date. Verify: `SWITCHER_APPSTORE=1 swift build` succeeds and the direct build contains no reference to it.
- [ ] 3.2 Log every evaluation as one `review:` line, with the unmet condition or `requested`. Verify: opening Settings in a development build below the threshold logs the count against the threshold.
- [ ] 3.3 Make sure no other path calls the coordinator, in particular the conversion path. Verify: a search of the sources finds exactly one call site, the Settings window.

## 4. The menu item

- [ ] 4.1 Read the listing's numeric Apple ID from App Store Connect and record it as a constant. Needs the user. Verify: the constant is set and `macappstore://apps.apple.com/app/id<ID>?action=write-review` opens the listing's review page.
- [ ] 4.2 Add "Rate Switcher3Way on the App Store…" to the App Store build's menu, with the string in all 16 interface languages. Verify: the item appears in the App Store build and not in the direct build, and choosing it opens the review page.

## 5. Verify and document

- [ ] 5.1 In a development App Store build with the thresholds temporarily lowered, confirm the review sheet appears over Settings and never while typing in another app. Restore the thresholds. Verify: the sheet appears over Settings, and a check of the source confirms the constants are back at 30, 7 and 120.
- [ ] 5.2 Add a line to the user guides (en, uk, ru) saying the App Store version may once ask for a rating, and where the menu item is. Verify: `bash build_app.sh` regenerates the Help pages.
- [ ] 5.3 After the first release that carries this, check once on a store-installed build that the request logs as expected. Verify: the `review:` lines from that build are recorded in this file.
- [ ] 5.4 Run `openspec validate ask-for-app-store-review --strict`. Verify: validation passes.

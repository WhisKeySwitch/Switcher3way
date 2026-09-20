## 1. Build flavour

- [x] 1.1 Add a `SWITCHER_APPSTORE` Swift compilation condition to `Package.swift`, and verify `swift build -c release` still succeeds with and without it
- [x] 1.2 Add a sandbox entitlements file (`signing/appstore.entitlements`) declaring `com.apple.security.app-sandbox`, and verify `codesign -d --entitlements -` reports the key on a build signed with it
- [x] 1.3 Teach `build_app.sh` an App Store flavour that sets the compilation condition, the sandbox entitlements and a distinct bundle identifier, and verify both flavours build from a clean tree and produce bundles with different `CFBundleIdentifier`
- [ ] 1.4 Verify both variants install and run simultaneously on one Mac, each holding its own permission grants
- [x] 1.5 Verify `Switcher3wCore` is compiled identically in both flavours — no `SWITCHER_APPSTORE` occurrences anywhere under `Sources/Switcher3wCore`

## 2. Password guard: three-state signals

- [x] 2.1 Extend the secure-field verdict so each signal reports positive, negative or unavailable, and verify the existing unsandboxed diagnostic still names every signal with unchanged verdicts
- [x] 2.2 Report the element-based signals as unavailable under `SWITCHER_APPSTORE`, and verify `diagpw` in the sandboxed flavour prints them as unavailable rather than negative
- [x] 2.3 Confirm the fail-open behaviour is unchanged in both flavours: every query failure still resolves to "not a password field", verified by the existing failure scenarios
- [ ] 2.4 Verify a focused password field in a browser is still reported as a password field in the sandboxed flavour, via the secure-input signal
- [ ] 2.5 Extend application-level suppression so a frontmost password manager suppresses conversion, feedback and the manual trigger when element inspection is unavailable, and verify with a password manager in the foreground

## 3. What else the sandbox affects

- [ ] 3.1 Verify conversion end to end in the sandboxed flavour: type a wrong-layout word, invoke the trigger, confirm the text is replaced and the layout switches
- [ ] 3.2 Verify conversion feedback falls back to the window anchor when no caret position resolves, and that it appears rather than being suppressed
- [ ] 3.3 Verify notifications work in the sandboxed flavour, including the learn-from-undo offer and the "couldn't rewrite here" error
- [ ] 3.4 Verify launch-at-login works in the sandboxed flavour and that the onboarding switch reflects its real state
- [ ] 3.5 Verify the in-app help window renders in the sandboxed flavour and that external links still open in the browser
- [ ] 3.6 Verify the debug log is written inside the container and that the diagnostic command-line modes work from the sandboxed bundle

## 4. Remove the updater from the App Store flavour

- [x] 4.1 Compile out `UpdateChecker` and `UpdateInstaller` under `SWITCHER_APPSTORE`, and verify the built binary imports no update code (no release-API string in the binary)
- [x] 4.2 Remove the "Check for Updates…" menu item and the automatic-update setting row in that flavour, and verify neither is present in the running app
- [x] 4.3 Verify the App Store flavour makes no network request on launch attributable to update checking
- [x] 4.4 Verify the direct flavour still checks, offers, verifies and installs updates exactly as before

## 5. Purchase

- [ ] 5.1 Create the App Store Connect record, register the bundle identifier, and define the auto-renewable subscription with an introductory free trial plus the non-consumable unlock; verify the products load in a sandbox StoreKit session
- [ ] 5.2 Implement entitlement resolution from the platform's current entitlements, and verify an active subscription, an active unlock and no purchase each resolve correctly
- [ ] 5.3 Implement the purchase and restore flows, and verify restore re-establishes entitlement after deleting and reinstalling the app
- [ ] 5.4 Implement the unpaid state: stop automatic conversion, show an unambiguous status-item state, offer the purchase options — and verify the reason is discoverable from the interface, not only the log
- [ ] 5.5 Verify an indeterminate entitlement (no network at launch) leaves the app working for that session, logs the reason, and re-checks rather than locking the user out
- [ ] 5.6 Verify the trial grants the full feature set on first launch with no sign-in prompt

## 6. Documentation and disclosure

- [ ] 6.1 State in the App Store listing and the user guide which password protection that variant does and does not provide, and verify the wording does not describe the two variants as equivalent
- [ ] 6.2 Complete the privacy labels truthfully — no data collected, nothing leaves the machine — and verify against what the app actually sends
- [ ] 6.3 Update the README so a visitor can tell which variant each channel provides and how they differ
- [x] 6.4 Remove the stale right-click → **Open** instruction for notarized direct releases, and verify the direct install path documented matches what a notarized DMG actually does
- [x] 6.5 Record the two-flavour build commands in `NOTES-3WAY.md` alongside the existing direct-channel instructions

## 7. Submission

- [ ] 7.1 Re-verify tasks 2.4, 3.1, 4.3 and 5.3 on a build produced by the App Store flavour of the build script — not a locally modified copy — and record the evidence
- [ ] 7.2 Submit for review, and on rejection record the stated reason in this change before altering anything
- [ ] 7.3 After approval, verify a purchase and a restore against the live listing on a Mac that has never run the app

## Why

If Accessibility or Input Monitoring is revoked while Switcher3Way is running, nothing notices. `monitoringActive` stays `true`, the event tap is dead, and the app goes on believing it is working. Nothing in the code re-checks after startup: there is no `CGEventTapIsEnabled` call anywhere, no health check, no watchdog.

The user sees an app that has silently stopped doing its job. That is this app's worst failure mode and its most common one — its successful state is invisible, so "doing nothing because it cannot" and "doing nothing because there was nothing to do" look identical from outside. The same shape has now produced five separate defects: the password guard's absent signals, purchase attempts that vanished, the chip with no anchor, the trigger with an empty buffer, and a permission grant nobody was watching for.

Revocation is not hypothetical. macOS drops these grants when an app's signature changes, and users toggle them off while debugging something else — both happened during the App Store work in September 2026.

## What Changes

- **Detect that monitoring has stopped working.** Periodically confirm the event tap is still enabled and the permissions still held, while monitoring is supposed to be active.
- **Say so, unmistakably.** The status item and menu must show that the app is not working and why. Silence is what makes this defect expensive.
- **Recover without a relaunch where possible.** A tap disabled by the system can be re-enabled; a permission genuinely revoked cannot, and the app should return to the state it uses when permissions were never granted — including the watcher added for the grant case, so that re-granting is picked up.
- **Correct a spec claim that is no longer true.** `permission-and-startup-lifecycle` says closing the onboarding window "loses nothing"; that was false until the grant watcher was added, and the spec should describe the guarantee rather than the window.

## Capabilities

### New Capabilities
None. This is a gap in an existing capability rather than a new one.

### Modified Capabilities
- `permission-and-startup-lifecycle`: currently describes permissions only as something checked at launch. It needs to state that the permissions and the event tap are the app's continuing preconditions, that losing either is detected, surfaced and recovered from, and that the app never presents itself as working when it is not.
- `menu-bar-ui-and-status-icon`: the status icon and menu must be able to express "not working, and here is why", distinctly from paused and from disabled.

## Impact

- **Code**: `AppDelegate` (the monitoring lifecycle and the watcher added for the grant case), `KeyboardMonitor` (tap health), the status icon and menu.
- **Cost**: a periodic check while monitoring is active. It must be cheap enough to run indefinitely and must not itself become a reason the app misbehaves.
- **Not in scope**: the sandboxed variant's inability to inspect Accessibility elements, which is a capability difference rather than a revocation, and is already covered in `password-field-protection`.

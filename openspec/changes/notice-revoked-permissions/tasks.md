## 1. Detection

- [x] 1.1 Expose the event tap's enabled state from `KeyboardMonitor` via `CGEvent.tapIsEnabled`, and verify it reads true while monitoring works
- [x] 1.2 Extend the existing permission watcher to run in both directions — watching for grants while monitoring is off, and for losses while it is on — keeping one timer and one cadence; verify from the log that exactly one timer runs in each state
- [x] 1.3 On a failing check, distinguish a disabled-but-recoverable tap from a revoked permission, and verify each is identified correctly by revoking Accessibility (permission) and by disabling the tap directly (recoverable)
- [x] 1.4 Verify the check cannot delay or interrupt a conversion: it acquires no locks and touches no conversion state, and a conversion performed while the timer fires is unaffected

## 2. Recovery

- [x] 2.1 Re-enable a tap that the system disabled, silently, and log it; verify monitoring continues with nothing shown to the user
- [x] 2.2 On a revoked permission, set `monitoringActive` false and hand over to the existing grant watcher, so recovery uses the same path as first-run rather than a second one; verify by revoking and then re-granting that monitoring resumes with no relaunch
- [x] 2.3 Verify a failed resume leaves the app in the not-working state rather than reporting itself recovered

## 3. Saying so

- [x] 3.1 Add a status-icon state for "not working through a fault", distinguishable from paused and from disabled; verify all three are visually distinct in the menu bar
- [x] 3.2 Add a menu line naming the missing permission and the way to restore it, legible rather than disabled grey — the same mistake as the expired-trial line in `ship-an-app-store-variant`; verify it is readable in both light and dark appearance
- [x] 3.3 Log every transition — detected, re-enabled, revoked, resumed — so that "it stopped working" can be answered from evidence; verify each appears in the debug log
- [x] 3.4 Verify the existing "Check Permissions…" item appears after a revocation, not only when permissions were never granted

## 4. Verification in the real cases

- [ ] 4.1 Revoke Accessibility on a running app: within a few seconds the icon shows a fault, the menu names it, conversion stops, and the log records it
- [ ] 4.2 Re-grant it: monitoring resumes with no relaunch, the icon returns to normal — and record the answer to the open question in `design.md` about whether a running process observes a fresh grant
- [ ] 4.3 Revoke Input Monitoring and confirm the same, since it is a separate grant with separate behaviour
- [ ] 4.4 Leave the app running normally for an extended period and confirm no measurable CPU cost and no spurious fault states
- [ ] 4.5 Verify in **both** flavours — the sandboxed build's permissions behave the same, but it has never been exercised here

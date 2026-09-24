## Context

See `proposal.md` — Why.

The relevant facts about the code as it stands:

- `AppDelegate.monitoringActive` is set `true` once, in `startMonitoring()`, and never re-examined.
- Nothing calls `CGEvent.tapIsEnabled`. The only tap-health handling is inside the event callback: `tapDisabledByTimeout` and `tapDisabledByUserInput` re-enable the tap. That works only while events still arrive, which is precisely not the case when the tap is dead.
- `AXIsProcessTrusted()` and `CGPreflightListenEventAccess()` are cheap, synchronous, and already called at launch.
- A watcher added in September 2026 polls for *missing* permissions to appear, every two seconds, but only runs while monitoring is off.

So the machinery for the opposite direction already exists and runs in the other state. This change is largely a matter of making the two halves symmetric.

## Goals / Non-Goals

**Goals:**

- Detect a dead tap or a withdrawn permission within a bounded time, without the user having to type something to find out.
- Make the not-working state visible and distinct from a deliberate pause.
- Recover silently where recovery is possible, and fall back to the existing not-yet-granted path where it is not.

**Non-Goals:**

- Detecting *why* macOS revoked a grant. The app cannot know, and guessing would produce a worse message than naming what is missing.
- Any change to conversion behaviour, the resolver, or the password guard.
- Notifying the user through a system notification. The status item and menu are enough; an alert for something the user may have done deliberately would be worse than the silence it replaces.

## Decisions

**Extend the existing watcher rather than adding a second timer.** A permission watcher already exists for the not-yet-granted state. Making it run in both states — watching for grants when monitoring is off, and for losses when it is on — keeps one timer, one cadence, and one place where "is this app actually working" is decided. Two independent timers checking overlapping conditions would eventually disagree, and the disagreement would be the bug.

*Amended during implementation:* the active state already had its own two-second poll — `iconRefreshTimer`, which keeps the menu-bar flag in sync and already called `watchPermissions()`. So the health check went there, and `watchPermissions()` became `checkMonitoringHealth()`. The decision's substance holds — no new timer, and one function decides whether the app is working — but the mechanism is one poll per state rather than a single poll in both. The grant watcher stays as it is, and the health check hands back to it on a revocation.

**Check the tap, not only the permissions.** A permission can be intact while the tap is disabled, and the reverse is possible during a grant transition. `CGEvent.tapIsEnabled` is the direct question and the cheap one; the permission calls say what to do about the answer. Checking only permissions would miss the case the in-callback handler cannot reach — a tap disabled while no events flow.

**Re-enable silently; report only what the user must act on.** A tap disabled by the system is recoverable and routine, so it is re-enabled and logged, with nothing shown. A revoked permission is not recoverable by the app, so it must be surfaced. The distinction matters: an app that announces every transient hiccup trains its user to ignore it.

**A revoked permission returns to the not-granted state, rather than inventing a third one.** `monitoringActive` goes false, the existing grant watcher takes over, and the onboarding window becomes reachable exactly as on first run. Re-granting then resumes through a path that already exists and is already exercised — instead of a separate recovery path that only runs in a rare case and therefore only fails in a rare case.

**Two seconds, and cheap.** The check is three synchronous calls. At that cadence the user notices within a couple of seconds, and the cost is immeasurable. Anything slower and the app appears broken for long enough to be reported; anything faster buys nothing.

## Risks / Trade-offs

- **A false positive stops a working app** → The check must only act on an unambiguous answer. `CGEvent.tapIsEnabled` returning false and a permission call returning false are both definitive; nothing here infers from silence or from absence of events, which is what made the original defect invisible in the first place.
- **The check runs during a conversion and interferes** → It touches no conversion state and holds no locks. The requirement that it cannot delay a conversion is in the spec so that a future implementation cannot quietly acquire one.
- **Revocation during a legitimate transition causes a flap** → Granting Input Monitoring already triggers a self-restart, and a changed signature drops grants at a point where the app is restarting anyway. If flapping appears in practice, the answer is a second consecutive failing check before acting, not a longer interval.
- **The status icon gains a third state and becomes noise** → Paused already has an indicator. The fault state must be distinguishable from it, which is a design constraint rather than a new mechanism.

## Observed in the field during implementation

On 2026-09-24, twenty minutes into ordinary use of 1.7.0 build 50 and seconds after a
conversion in Telegram, the event tap stopped and `CGEvent.tapEnable` would not restore it:

```
09:57:39  auto: convert 8 keys → Ukrainian-PC
09:58:26  trig: armed (key=56)        ← no CONVERT followed
09:58:29  health: event tap disabled and could not be re-enabled — monitoring stopped
09:58:31  Event tap created and enabled successfully / Monitoring started successfully
```

Nobody staged this. It is the defect the change exists for, occurring unprompted, and before
the change it would have been permanent — the in-callback re-enable cannot run for a tap that
delivers no events. Recovery took about five seconds and ran entirely through the grant
watcher, i.e. the path first launch exercises every time.

Unresolved: whether the tap was genuinely dead, or whether `reenableTap()` read
`tapIsEnabled == false` in a race immediately after enabling. The armed trigger at 09:58:26
producing no conversion leans toward a real death, but that is suggestive rather than
conclusive, and it is the difference between a fault that is always real and one that can
fire spuriously — the risk named below.

Cost over the same 64-minute run: 0.1% CPU, 50 MB RSS.

## Migration Plan

Additive and self-contained. No stored state, no format change, nothing a user must do. If the check proves troublesome it can be removed without leaving anything behind.

Worth shipping to the direct channel first: revocation is more common there, because that build's Developer ID signature is what changes between local builds, and its users are more likely to be toggling permissions while testing something else.

## Open Questions

- ~~Whether a running process reliably observes a *newly granted* permission, or whether macOS caches the authorization per process.~~ **Answered 2026-09-24, for Accessibility: yes.** Carried unresolved from `ship-an-app-store-variant` 3b.3, where the retest self-restarted before the watcher could demonstrate it. Measured on macOS 27 with 1.7.0 build 50: Accessibility revoked at 09:24:33 and detected in the same second, re-granted at 09:26:19 and monitoring running in the same second, with no relaunch — and conversion actually worked afterwards, which the log alone could not have shown. A tap created after a fresh grant delivers events; the authorization is not cached against the process.

  Input Monitoring is a separate question and may well answer differently: the onboarding flow already restarts the app when that one is granted, because macOS was observed to require it. Task 4.3 is where that gets established rather than assumed.

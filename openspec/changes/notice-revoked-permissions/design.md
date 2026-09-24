## Context

See `proposal.md` — Why.

The relevant facts about the code as it stands:

- `AppDelegate.monitoringActive` is set `true` once, in `startMonitoring()`, and never re-examined.
- Nothing calls `CGEventTapIsEnabled`. The only tap-health handling is inside the event callback: `tapDisabledByTimeout` and `tapDisabledByUserInput` re-enable the tap. That works only while events still arrive, which is precisely not the case when the tap is dead.
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

**Check the tap, not only the permissions.** A permission can be intact while the tap is disabled, and the reverse is possible during a grant transition. `CGEventTapIsEnabled` is the direct question and the cheap one; the permission calls say what to do about the answer. Checking only permissions would miss the case the in-callback handler cannot reach — a tap disabled while no events flow.

**Re-enable silently; report only what the user must act on.** A tap disabled by the system is recoverable and routine, so it is re-enabled and logged, with nothing shown. A revoked permission is not recoverable by the app, so it must be surfaced. The distinction matters: an app that announces every transient hiccup trains its user to ignore it.

**A revoked permission returns to the not-granted state, rather than inventing a third one.** `monitoringActive` goes false, the existing grant watcher takes over, and the onboarding window becomes reachable exactly as on first run. Re-granting then resumes through a path that already exists and is already exercised — instead of a separate recovery path that only runs in a rare case and therefore only fails in a rare case.

**Two seconds, and cheap.** The check is three synchronous calls. At that cadence the user notices within a couple of seconds, and the cost is immeasurable. Anything slower and the app appears broken for long enough to be reported; anything faster buys nothing.

## Risks / Trade-offs

- **A false positive stops a working app** → The check must only act on an unambiguous answer. `CGEventTapIsEnabled` returning false and a permission call returning false are both definitive; nothing here infers from silence or from absence of events, which is what made the original defect invisible in the first place.
- **The check runs during a conversion and interferes** → It touches no conversion state and holds no locks. The requirement that it cannot delay a conversion is in the spec so that a future implementation cannot quietly acquire one.
- **Revocation during a legitimate transition causes a flap** → Granting Input Monitoring already triggers a self-restart, and a changed signature drops grants at a point where the app is restarting anyway. If flapping appears in practice, the answer is a second consecutive failing check before acting, not a longer interval.
- **The status icon gains a third state and becomes noise** → Paused already has an indicator. The fault state must be distinguishable from it, which is a design constraint rather than a new mechanism.

## Migration Plan

Additive and self-contained. No stored state, no format change, nothing a user must do. If the check proves troublesome it can be removed without leaving anything behind.

Worth shipping to the direct channel first: revocation is more common there, because that build's Developer ID signature is what changes between local builds, and its users are more likely to be toggling permissions while testing something else.

## Open Questions

- Whether a running process reliably observes a *newly granted* permission, or whether macOS caches the authorization per process. Established as unresolved in `ship-an-app-store-variant` 3b.3: the retest self-restarted before the watcher could demonstrate it. It affects how well recovery works here, but not whether detection does, and the answer will fall out of the first revoke-and-restore test.

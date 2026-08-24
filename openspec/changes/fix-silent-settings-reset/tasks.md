## 1. Reproduce the failure without needing a trimmed build

- [x] 1.1 A malformed `settings.json` yields defaults, **no log line, and no user-visible sign.**
      Confirmed against a build of the shipped code with a file truncated mid-array — the shape a
      power loss during a write actually produces.
- [x] 1.2 A subsequent save overwrites the malformed file, making the loss permanent — and it is
      **worse than the proposal assumed.** No user action is needed at all: the background update
      check writes `LastUpdateCheck` and saves within seconds of launch. Measured, the file went from
      the user's 8 denied apps and `NeverConvertWords: ["XBO"]` to bare defaults **nine seconds after
      the app started**, with the user having touched nothing.

## 2. Fix

- [x] 2.1 `Load()` distinguishes "file absent" (quiet defaults, nothing was lost) from "file present
      but unreadable" (a failure).
- [x] 2.2 Reported through `Diagnostics.LogAlways`, never `Log` — the debug flag lives in the file
      that just failed, so the one switch that would have recorded this is off in exactly the case
      that needs it.
- [x] 2.3 The unreadable file is moved to `settings.json.bad` before anything can replace it; an
      older `.bad` is discarded so only the most recent failure is kept.
- [x] 2.4 The user is told, through the existing error-notification path (`Toast.ShowError`), with a
      string added in all three interface languages.
- [x] 2.5 A failed load cannot become a permanent erasure. Implemented more simply than this task
      first described: rather than flagging the instance and teaching `Save()` to refuse, the
      original is **moved aside during the load**, so the file a later save writes to is a different
      one and the preserved copy is never in its path. `LoadFailed` still exists, but only to decide
      whether to notify. Fewer moving parts, and it holds even if a save happens from a code path
      nobody remembered to guard.

## 3. Verify

Against a published build, driving the real binary and reading its own log.

- [x] 3.1 Malformed file: reported (`settings: could not be read (JsonException: …)`), preserved
      (`settings: the unreadable file was kept as settings.json.bad`), original content intact in the
      `.bad` file, defaults used for the session.
- [x] 3.2 Absent file: silent defaults, nothing logged, no `.bad` written.
- [x] 3.3 Readable file: no log lines, no `.bad`, and the real settings survive untouched — the
      exception list and all eight denied apps still present afterwards.
- [x] 3.4 A settings file carrying a field this build has never heard of loads normally rather than
      being treated as corrupt, so a downgrade after a future release does not destroy preferences.
- [x] 3.5 The notification itself, on a packaged build — and it was right to insist. The first
      packaged run logged `toast: not registered — this and any further notifications are dropped`,
      because `Tray` raised the notification ten lines before `Toast.Initialize` registers with the
      platform. **The user would never have seen it.** Unpackaged runs log the same line for an
      innocent reason, so nothing short of a packaged build could have caught it. Notification moved
      after registration.
- [x] 3.6 Delivery verified objectively rather than by watching for a banner: Windows records every
      delivered notification in `wpndatabase.db`, and the entry is there with the right text.
- [x] 3.7 Corrected the heading while reading that entry. It arrived under the generic
      `toast.error.title` — "Switcher3way couldn't fix that" — which belongs to a failed conversion
      and flatly contradicts this message. `ShowError` gained a title overload and the notification
      its own heading in all three languages: "Your settings were reset".

## 4. Test packages must not disturb the installed app

- [x] 4.1 The test packages were built with a distinct `Identity/Name` and their own activator CLSID,
      so they installed **beside** the Store build instead of replacing it — a plain sideload shares
      the package name and silently removes the Store entry, which happened once already.
- [x] 4.2 Afterwards: test packages removed, the stale 0.3.1 developer package removed, the real
      settings file restored byte-for-byte, and the Store build confirmed running.

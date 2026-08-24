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
- [ ] 3.5 **Needs a packaged build:** the notification itself. Unpackaged builds log
      `toast: not registered — this and any further notifications are dropped`, so the user-facing
      half of 2.4 is unverified. Notifications have to be tested in the flavour that ships; that
      lesson cost two certification failures.

## 1. Reproduce the failure without needing a trimmed build

- [ ] 1.1 Test that a malformed `settings.json` today yields defaults, no log line, and no user-visible sign.
- [ ] 1.2 Test that a subsequent `Save()` overwrites the malformed file, making the loss permanent.

## 2. Fix

- [ ] 2.1 `Load()` distinguishes "file absent" (quiet defaults) from "file present but unreadable" (a failure).
- [ ] 2.2 Report through `Diagnostics.LogAlways`, never `Log` — the debug flag lives in the file that failed.
- [ ] 2.3 Preserve the unreadable file as `settings.json.bad` before anything can replace it, keeping only the most recent one.
- [ ] 2.4 Surface it to the user through the existing error-notification path.
- [ ] 2.5 Mark the instance as "loaded from a failure" so the first `Save()` cannot quietly erase the preserved original.

## 3. Verify

- [ ] 3.1 Malformed file: reported, preserved, user told, defaults used for the session.
- [ ] 3.2 Absent file: silent defaults, nothing reported, nothing written until the user changes something.
- [ ] 3.3 Readable file: byte-identical behaviour to today, including no new log noise.
- [ ] 3.4 A settings file containing an unknown future field still loads rather than being treated as corrupt.

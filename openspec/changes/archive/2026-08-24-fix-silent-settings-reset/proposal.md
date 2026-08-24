## Why

`SettingsManager.Load()` reads the settings file inside a bare `catch { }` and returns a fresh
`SettingsManager` on any failure. `DebugLog` defaults to `false`. Put those two together and an
unreadable settings file costs the user everything they have configured — exception lists, denied
apps, the trigger key, the ambiguous-language preference, onboarding state — **with no message, no
log line, and no way to find out.** The one switch that would have recorded the failure lives in the
file that just failed to load, so it switches itself off.

Worse, the loss is not confined to that session, and it needs no help from the user. The defaults are
held in memory as if they were the real settings, and the next `Save()` writes them over the file —
but that save is not waiting for anyone to toggle anything. The background update check stamps
`LastUpdateCheck` and saves on its own. Measured against a build of the shipped code: a settings file
holding eight denied apps and a never-convert entry became bare defaults on disk **nine seconds after
launch**, with nothing touched. A failed read turns itself into a permanent erasure.

This was found while measuring a trimmed build, where JSON deserialization genuinely fails, and the
app kept converting text perfectly while quietly running on defaults. But trimming is not the
hazard; it only made an existing one visible. A truncated write during a crash or power loss, a disk
error, a hand-edit with a trailing comma, or a settings file written by a newer version all land in
the same `catch`.

## What Changes

- **Tell "no file yet" apart from "a file I could not read."** A first run has no settings and must
  quietly use defaults. An existing file that fails to parse is a failure and must behave like one.
- **Say so unconditionally.** The failure is reported through the always-on log, not the debug log —
  the debug flag cannot be trusted here, because it is read from the file that just failed. This is
  the same reasoning that made every keep-decision loggable in the typo-guard work: a fault nobody
  can observe is indistinguishable from no fault.
- **Do not overwrite what could not be read.** The unreadable file is preserved as
  `settings.json.bad` before anything replaces it, so a recoverable file is recoverable and a
  reportable bug is reportable.
- **Tell the user.** Losing an exception list silently is exactly the class of thing this app is
  supposed to be careful about; a failed load raises the same notification surface used for other
  errors the user could otherwise never learn about.

## Impact

No behaviour changes when the settings file is readable, which is every normal run. What changes is
the failure path, which today is silent and destructive and afterwards is loud and reversible.

This is worth doing on its own account and is not blocked by, nor blocking, the packaging work in
`trim-the-bundled-runtime` — though it removes one of the three defects that work has to solve.

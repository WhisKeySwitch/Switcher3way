## Context

The Store build has no in-app path to a review, and the app's design removes every natural moment for
one (`proposal.md`). What exists to build on:

- `Engine` already raises `Converted` for every applied conversion, `Undone` when the user reverses one,
  and `Notify` when a rewrite could not be applied. `Tray` subscribes to all three and marshals them to
  the UI thread. Those three events are the entire evidence base this feature needs.
- `PackageInfo.IsPackaged` already branches the updater and "start with Windows"; `Launch.Open` already
  routes URIs through `Windows.System.Launcher` under `PACKAGED` so no `Process.Start` reaches the
  binary the App Certification Kit inspects.
- `UpdatePromptWindow` is the established pattern for a modal-feeling prompt in an app with no main
  window: an `OverlappedPresenter.CreateForDialog()` window, always-on-top, hidden from switchers.
- `SettingsManager` is a plain JSON document at `%APPDATA%\Switcher3way\settings.json`, shared by both
  flavours and not redirected for the packaged build.
- Diagnostics switches (`diagtoast`, `diaghint`, `diagcaret`…) are argv-driven and wired in
  `App.xaml.cs`, which is how UI surfaces in this app are driven on demand rather than waited for.

The binding constraint is not technical. It is that this is a keyboard utility whose users are typing
when it runs, and a window that steals focus mid-word is both an interruption and a correctness problem:
`KeyboardMonitor` clears its buffers on app switch precisely so a rewrite never targets text the caret
has left.

## Goals / Non-Goals

**Goals:**

- One ask, at a moment the app has earned and the user is not mid-sentence.
- A single click to never see it again, honoured permanently.
- A decision procedure that is pure, testable without the app, and logs its reason every time it
  declines — including when it declines silently, which is almost always.
- Zero footprint in the MSI build and zero new network traffic in either.

**Non-Goals:**

- Measuring whether the ask works. Partner Center reports review volume; this change ships no analytics
  of its own and will not learn which asks converted.
- Asking again on later versions, or a second independent ask for the MSI channel.
- Any macOS counterpart. The macOS app is not in a store and has nothing to ask for.

## Decisions

### D1 — The milestone is a pure predicate over a snapshot, evaluated in `StoreReview`

`StoreReview.ShouldAsk(ReviewState state, ReviewContext now)` returns either `Ask` or
`Decline(reason)`. `ReviewState` is the persisted counters and ask-state; `ReviewContext` is everything
read live (paused, enabled, onboarding done, secure field focused, denied app foreground, seconds since
the last keystroke, minutes since the last failed rewrite or undo, `IsPackaged`).

The predicate touches no Windows API, so it is unit-testable the way `Switcher3way.Core` is — which is
the point of that split in this repo. *Alternative considered:* inline the conditions in `Tray` where the
events arrive. Rejected: nine conditions that can each independently suppress a once-ever prompt are
exactly the shape of code that is never exercised and silently always-false.

### D2 — Count fixes the user got, not cycle steps, and decrement on undo

`Engine.RaiseConverted` fires on four paths: the auto conversion, the retro-correction, the phrase-locked
conversion, and **each step of the manual cycle**. Counting the event as-is would score three for one user
tapping the trigger three times to cycle through candidates — one fix, counted thrice.

**Revised once the field log arrived (D11).** The first version of this decision excluded manual
conversions entirely, on the reasoning that the user did that work themselves. The log says manual fixes
*outnumber* automatic ones, 66 to 48 — so excluding them measures under half of what the app does, and
under-measures hardest for the people who use it most deliberately, since auto recall sits at 57–70% and
the trigger is how you cover the rest. A trigger tap that fixes a word is the app being useful.

So `ConversionInfo` carries `Auto` / `Retro` / `Manual` / `ManualCycleStep`, and only the last is
excluded: the second and third tap steer one fix through the candidates rather than making three fixes.
`Undone` decrements, floored at zero — a conversion the user reversed is one the app got wrong, and
cycling back to the original fires `Undone`, so a rejected manual fix nets to nothing.

*Alternative considered:* count every `Converted` event and accept the inflation. Rejected — it makes the
threshold meaningless and biases the ask toward users who are cycling candidates, which is what people do
when detection is failing them. *Also considered:* weight a manual fix lower than an automatic one, on
the grounds that an unprompted fix is stronger evidence. Rejected as a second ungrounded constant that no
available data could settle.

### D3 — The ask waits for an idle gap, and is scheduled rather than shown inline

The threshold is crossed during a conversion, but showing the window there would put it on screen
mid-word. Instead `Tray`'s existing 400 ms poll (not a new timer) re-checks, and shows the ask at the
first moment with **no keystroke for 20 seconds** and no other Switcher3way window open.

There is deliberately no persisted "armed" flag — an earlier draft had one and it was removed as dead
weight. Eligibility is re-derived from the counters on every check, so a threshold crossed in one session
is still crossed in the next: a pending ask survives a restart without anything being stored to say so,
and there is no second piece of state that can fall out of step with the counts.

20 s is a judgement, not a measurement, and is cheap to change; the tasks record it as such.

### D4 — The in-app ask comes first; the Store dialog only on "Rate it"

`RateWindow` mirrors `UpdatePromptWindow` (dialog presenter, always-on-top, not in switchers) with three
actions: **Rate it** (accent), **Not now**, *No thanks* (hyperlink, the de-emphasised position the update
prompt gives Skip). Only **Rate it** reaches the Store.

Two reasons for the preamble, rather than calling `RequestRateAndReviewAppAsync` directly. First, the
Store dialog is Microsoft's and cannot carry an opt-out, so without a preamble there is no click that
means "never ask me again" — only "close", which is indistinguishable from "later". Second, the Store
dialog in a desktop app must be parented to a window (D5), and a tray app has none; the preamble window
is that parent, so it is needed either way.

### D5 — `StoreContext` must be initialised with an HWND, and the fallback is a URI, never a process

```
var ctx = StoreContext.GetDefault();
InitializeWithWindow(ctx, WindowNative.GetWindowHandle(rateWindow));
var result = await ctx.RequestRateAndReviewAppAsync();
// result.Status: Succeeded | CanceledByUser | Error | NetworkError
```

`GetDefault()` on a desktop app returns a context with no window association, and the dialog fails
without one. On `Error` or `NetworkError` the fallback is
`ms-windows-store://review/?ProductId=9MXFXL7GG3C5` through `Launch.Open`, which under `PACKAGED` is
`Windows.System.Launcher.LaunchUriAsync`. Explicitly **not** `Process.Start`: the App Certification Kit
reads the binary, and `UpdateInstaller.Store.cs` exists in this repo solely because unreachable
`Process.Start` still fails that test.

Every status is logged. `CanceledByUser` is treated as "asked and done", not as a reason to retry — the
user has now seen the Store's own dialog and declined it.

### D6 — Ask state is a small enum, and "No thanks" is terminal

`ReviewAskState`: `NotAsked` → `Asked` → (`ReArmed` → `AskedTwice`) or `Retired`.

- **Rate it** → `Retired`, regardless of what the Store dialog then returns. Someone who clicked Rate has
  given their answer; whether Microsoft's dialog succeeded is not their problem.
- **Not now** → `ReArmed`, with the second threshold at 3× the first and at least 30 days later. One
  re-ask, invited.
- **No thanks** → `Retired`, permanently, with no version or time condition that can undo it.
- Closing the window with the title-bar X → treated as **Not now**, the forgiving reading.

Stored as a string so an unknown value written by a newer build degrades to "do not ask" rather than to
"ask again".

### D7 — Suppression reasons are logged by name, every time

The reasons are a closed set — `not-packaged`, `already-answered`, `below-threshold`,
`too-few-active-days`, `too-new`, `disabled-or-paused`, `onboarding-incomplete`, `secure-field`,
`denied-app`, `recent-failure`, `recent-undo`, `user-typing`, `window-open`, `settings-load-failed`.
Logged at most once per reason per session: the condition is checked every 400 ms, and logging each check
would bury the log.

This is the project's standing rule applied to a new surface. A prompt that is correctly suppressed and a
prompt whose code never ran are indistinguishable on screen, and this repo has already lost a test
session to that ambiguity once.

### D8 — Counters are integers in `settings.json`, and they survive a channel switch

`ConversionCount` (int), `FirstRunUtc` (date), `ActiveDays` (int), `LastActiveDay` (date, so `ActiveDays`
increments once per day), `ReviewAskState`, `ReviewAskedUtc`. No words, no per-conversion timestamps,
nothing transmitted. The debug log already refuses to record which key was pressed; this holds that line.

A consequence worth stating because it surprises: `%APPDATA%\Switcher3way` is **not** redirected for the
packaged build, so a user who installed the MSI first and later moved to the Store arrives with counters
already accumulated and may be asked almost immediately. That is defensible — the app did earn it — but it
should be a decision rather than a discovery, and it is the one path where "once ever" could feel abrupt.

The settings quarantine path (`settings.json.bad`) resets the counters to zero, which delays the ask.
Acceptable; the opposite failure would not be.

### D9 — Testing: the predicate is unit-tested, the window is `diagreview`, the dialog needs a flight

The Store review dialog **does not work in a sideloaded package** — it requires a Store-issued licence —
so the final surface cannot be verified by the usual `build-msix.ps1 -Sideload -Sign` loop. Three layers
instead:

1. `StoreReview.ShouldAsk` — unit tests over the state/context matrix, covering every suppression reason
   and both terminal states. No app, no permissions, no package.
2. `diagreview` — a new argv switch that arms and shows `RateWindow` immediately, bypassing every
   threshold. Verifies the window, its localisation, the three buttons and the state transitions in
   either flavour.
3. `diagreview-store` — goes straight to `RequestRateAndReviewAppAsync` and logs the status. In a
   sideload this is *expected* to log a failure status, and that is the test: it proves the call path and
   the HWND initialisation are wired, and separates "the call failed" from "the call was never made".

The dialog itself is verified once, through a Partner Center **package flight** to the developer's own
account, before the public release. `windows/RELEASING.md` gains that step. This is the "verify in the
flavour that ships" rule — learned here through three certification failures — applied to a surface where
sideloading genuinely cannot stand in.

### D10 — Localisation is part of the feature, not a follow-up

An unlocalised prompt asking for a public action in a keyboard utility reads as malware. The new strings
go into all 16 `Loc.cs` languages in this change. `Loc.T` already falls back to English, but falling back
here is a defect, not graceful degradation.

### D11 — The thresholds are a judgement, checked against a field log rather than derived from one

Task 1.1 went looking for a conversion rate in the Windows log and found none: 48 days, 25 applied
conversions, every one a test word, and the log only exists on days somebody enabled debug logging.
The macOS install supplied what that could not — eight days of continuous logging in ordinary use
(2026-09-29→10-06, post-1.6.0): **114 fixes over 8 calendar days, 48 automatic and 66 by trigger, on 7
active days**. Logging ran throughout, so that is a per-calendar-day rate rather than a per-session one.

**Shipping: 75 conversions, 5 active days, 14 days installed.**

This is deliberately not called a measurement. One install is a sample of one, and of the heaviest user
this app will ever have; calibrating a population threshold from the most active user sets it too high.
What a single subject legitimately supports is *falsification*, and it does not falsify these: at 14.3
fixes a day, 75 arrives in five days, so the install age is what binds for that user and the ask lands
near day 14; a user at a third of the rate meets both constraints together at about three weeks, which
is where this is aimed.

An earlier draft of this design deferred the thresholds until a month of counter data existed. That was
wrong, and the reasoning is worth keeping because it is a tempting mistake in this repo specifically.
It imported "measure, don't assert" from the detection core, where the rule is earned — intuition about
conversion has been measurably wrong more than once (the Bulgarian collision matrix contradicted the
prediction twice), and a false conversion costs the rest of the sentence. A review prompt has neither
property: no mechanism makes intuition systematically wrong here, and the cost of being wrong is one
dismissible dialog. The failure modes are also asymmetric — too high and the ask never fires, which is
precisely what deferring guarantees; too low and it arrives early, where D6's re-arm absorbs it. So the
deferral chose the worse outcome with certainty in order to avoid risking the milder one, while buying
data that was n=1 and biased toward heavy use.

`Calibrated: false` survives, not as the shipping state but as the **rollback switch**: setting it
disables the automatic ask entirely and leaves the manual entry standing. That is the abandon path if
the prompt proves unwelcome, and it stays under test.

## Risks / Trade-offs

- **It is still a nag, and nags cost uninstalls** → Capped at two asks ever, one of them only on
  invitation; suppressed near any evidence the app has just misbehaved; a permanent single-click opt-out.
  If a Store review ever reports the prompt as intrusive, the abandon condition is explicit: default
  `ReviewAskState` to `Retired` and leave only the manual menu entry.
- **The thresholds are guesses until task 1 runs** → No threshold ships without being checked against the
  field log. If the log says 100 conversions is reached on day one by an ordinary user, the number moves;
  if a week of typing produces 20, it moves the other way. The abandon condition for the automatic ask is
  a log that cannot distinguish a committed user from a trial one.
- **The Store dialog cannot be tested locally** → D9's three layers plus a package flight. The residual
  risk is that the flight is skipped under release pressure and the dialog ships unseen, which is why
  `RELEASING.md` carries it as a checklist line rather than this document as prose.
- **Counting conversions couples a cosmetic feature to the engine's hot path** → The counter is an int
  increment on an event `Tray` already handles on the UI thread. It must never throw into the conversion
  path: the subscription is wrapped, and a failure to count is logged and ignored.
- **Carried-over counters from an MSI install can make the ask appear on day one of a Store install** →
  D8 accepts this deliberately. If it proves jarring, the cheap fix is to require the install to have been
  packaged for at least 7 days, which needs one more persisted date.
- **A settings-file corruption resets the counters and re-arms a retired ask** → The quarantine path
  already logs loudly, and the re-ask would be at most one. Not worth a second store.

## Open Questions

- **Threshold values** — resolved by task 1 against the field log, not here.
- **Should the manual "Rate Switcher3way" row appear in the tray flyout, the Settings About tab, or
  both?** Proposed: both. The flyout is where a tray app's users look; About is where this kind of row
  conventionally lives. Cheap to do both, and the row is absent in the MSI build either way.

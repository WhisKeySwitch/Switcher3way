## 1. Calibrate the thresholds before writing the code they go in

Nothing below ships on a guessed number. The field log behind 1.6.0 counts auto *decisions*, and the
app's most common decision is to leave a word alone, so the conversion rate has to be extracted rather
than read off.

- [x] 1.1 From the twelve-day field log (and any later log available), count **applied auto
      conversions** per day and per distinct active day, separating them from keeps, deferrals and
      manual triggers.

      **Done, and the answer is that no usable field data exists.** The Windows log on the development
      machine spans 48 days (2026-08-19 → 2026-10-05, 13,566 lines) and contains **25 applied auto
      conversions on 6 distinct days, and 0 manual triggers**. They are visibly a test set rather than
      typing — `привіт` ×6, `апка` ×3, `Kyiv` ×3, `столиця` ×2, `заедно` [bg] on the day of the
      Bulgarian work, `айді` on the day of the gibberish-rescue work — and the four highest-volume days
      (2026-09-10→13, 8,777 lines) applied **nothing at all**, being `diagpw` and `rewrite` runs.

      Three independent reasons it cannot calibrate a threshold:
      1. One subject, who was testing rather than typing, so there is no ordinary user in the data.
      2. Debug logging is off by default, so the log covers only the 13 days somebody enabled it — it
         structurally cannot measure a rate per calendar day.
      3. The macOS log behind 1.6.0 is not available here, and counted decisions rather than applied
         conversions in any case. `FieldLogMissesTests.cs` preserves its *cases*, not its counts.

      The placeholder threshold was ≥100 conversions. On the only Windows data that exists a user
      reaches 25 in seven weeks, so the ask would never fire.

- [x] 1.2 **Thresholds set: 75 conversions, 5 active days, 14 days installed.** Checked against eight
      days of continuous macOS field logging in ordinary use (2026-09-29→10-06, post-1.6.0, debug
      logging on throughout, so the rate is per *calendar* day rather than per day somebody enabled it):

      | | count | per day |
      |---|---|---|
      | Automatic conversions applied | 48 | 6.0 |
      | Manual trigger conversions | 66 | 8.3 |
      | **Total fixes** | **114** | **14.3** |
      | Active days / days logged | 7 / 8 | — |

      The numbers are a judgement *checked* against that log, not derived from it — one install is a
      sample of one, and of the heaviest user this app has. What a single subject can legitimately do
      is falsify, and it does not: at 14.3 fixes a day, 75 is reached in five days, so for that user
      the 14-day install age binds and the ask lands about day 14; a user at a third of the rate meets
      both constraints together at roughly three weeks.

      **The deferral was dropped, and dropping it was right.** It imported "measure, don't assert" from
      the detection core, where that rule is earned — intuition about conversion has been measurably
      wrong more than once, and a false conversion costs the rest of the sentence. A review prompt has
      neither property, and its failure modes are asymmetric: too high and the ask never fires, which is
      exactly what deferring guarantees; too low and it arrives early, where the re-arm absorbs it.
      Deferring chose the worse outcome with certainty in order to avoid risking the milder one. It
      would also have bought n=1 data biased toward heavy use, which sets thresholds too high — back to
      failure mode one.

- [x] 1.3 Re-arm threshold: 3× conversions and ≥30 days, as proposed. Unchanged, and deliberately
      generous: it is the hedge that makes setting the first threshold by judgement safe.

- [x] 1.4 **Abandon condition — evaluated and not taken.** It was written for a log in which committed
      and trial users look alike; the Windows log contained neither, and the macOS log in 1.2 separates
      them cleanly. `Calibrated: false` survives as the rollback switch rather than as the shipping
      state: flipping it disables the automatic ask completely and leaves the manual entry standing,
      which is the abandon path if the prompt ever proves unwelcome.
      `An_uncalibrated_threshold_still_refuses_outright` keeps that path tested. See `design.md` D11.

## 2. Count what the app has done, locally

- [x] 2.1 `ConversionInfo` gains a source; `Engine.RaiseConverted`'s four call sites each pass theirs.
      **Revised after 1.2:** the field log showed manual conversions outnumbering automatic ones 66 to
      48, so counting only the automatic ones would measure under half of what the app does — and would
      under-measure hardest for the users who rely on it most, since auto recall sits at 57–70%. The
      source is therefore `Auto` / `Retro` / `Manual` / `ManualCycleStep`, and only the last is excluded:
      a further tap steers one fix rather than making another. See design D2.
- [x] 2.2 `SettingsManager`: `ConversionCount`, `FirstRunUtc`, `ActiveDays`, `LastActiveDay`,
      `ReviewAskState` (string), `ReviewAskedUtc`. Add them to the source-generated JSON context, and
      confirm a settings file written by 0.6.1 still loads (missing properties take their defaults).
- [x] 2.3 `Tray` increments on `Auto`/`Retro` conversions and decrements on `Undone`, floored at zero.
      `ActiveDays` increments at most once per calendar day via `LastActiveDay`.
- [x] 2.4 Wrap the counting so it can never throw into the conversion path; a failure to count logs and
      is ignored.
- [x] 2.5 Saving: do not write `settings.json` on every conversion. Accumulate in memory and persist on
      a day change, on the ask, and on shutdown.
- [x] 2.6 Confirm nothing recorded is or could become typed text. The counters are integers and dates
      only.

## 3. The decision: `StoreReview.ShouldAsk`

- [x] 3.1 `ReviewState` (persisted) and `ReviewContext` (live) records, and
      `StoreReview.ShouldAsk(state, context)` returning `Ask` or `Decline(reason)` — pure, no Windows
      API, no I/O.
- [x] 3.2 Implement every suppression reason as a named constant: `not-packaged`, `already-answered`,
      `below-threshold`, `too-few-active-days`, `too-new`, `disabled-or-paused`, `onboarding-incomplete`,
      `secure-field`, `denied-app`, `recent-failure`, `recent-undo`, `user-typing`, `window-open`,
      `settings-load-failed`.
- [x] 3.3 Unit tests over the matrix: each reason suppresses on its own; the `Ask` case requires all of
      them clear; `Retired` and `AskedTwice` are terminal; an unrecognised `ReviewAskState` string
      declines. These run in the existing `dotnet test` suite with no app and no package.
- [x] 3.4 Log the declining reason once per reason per session (the check runs on the 400 ms poll).

## 4. The ask: `RateWindow`

- [x] 4.1 `RateWindow.xaml` / `.xaml.cs` modelled on `UpdatePromptWindow`: dialog presenter,
      always-on-top, `IsShownInSwitchers = false`. **Rate it** (accent) · **Not now** · *No thanks*
      (hyperlink).
- [x] 4.2 Arming and showing: crossing the threshold arms; `Tray`'s existing poll shows the window at
      the first moment with no keystroke for 20 s and no other Switcher3way window open. No new timer.
      Record 20 s as a judgement, not a measurement.
- [x] 4.3 A pending ask survives the session. Built *without* a persisted "armed" flag, which the
      design had assumed: eligibility is re-derived from the counters on every check, so a threshold
      crossed in one session is still crossed in the next, and there is no second piece of state to fall
      out of step with the counts. The flag was written and then removed as dead weight.
- [x] 4.4 State transitions per design D6, including the title-bar X reading as **Not now**.
- [x] 4.5 Six new strings across all 16 `Loc.cs` languages. An English fallback here is a defect, not
      graceful degradation — check each language actually has them.

## 5. The Store call

- [x] 5.1 `StoreContext.GetDefault()`, `IInitializeWithWindow.Initialize` with the `RateWindow` HWND,
      then `RequestRateAndReviewAppAsync`. Without the HWND the dialog does not appear in a desktop app.
- [x] 5.2 Log every status. `CanceledByUser` ends the flow — the user has seen the Store's dialog and
      declined it; it is not a reason to retry.
- [x] 5.3 On `Error` / `NetworkError`, fall back to `ms-windows-store://review/?ProductId=9MXFXL7GG3C5`
      via `Launch.Open`. Verify by inspection that no `Process.Start` reaches the packaged binary — the
      App Certification Kit reads it, which is why `UpdateInstaller.Store.cs` exists.
- [x] 5.4 Gate the whole feature on `PackageInfo.IsPackaged`. Decide and record whether the Store call
      lives behind `#if PACKAGED` like `Launch`, or behind a runtime check; nothing inspects the MSI
      binary, so a runtime check is sufficient unless the reference itself is a problem.

## 6. The manual entry point

- [x] 6.1 "Rate Switcher3way" row in `TrayFlyoutWindow`, present only in a packaged build — absent, not
      disabled.
- [x] 6.2 The same row in Settings → About, taking the identical path.
- [x] 6.3 Confirm it still works after the user has chosen **No thanks**: the permanent decline retires
      the *ask*, not the user's own ability to rate.

## 7. Verify in the flavour that ships

- [x] 7.1 `diagreview` — argv switch in `App.xaml.cs` that arms and shows `RateWindow` immediately.
      Verified on the unpackaged build: the window renders with its text, the three buttons and their
      emphasis; **Rate it** drives state to `Retired` and then correctly logs
      `unpackaged build — no Store listing to rate` instead of attempting the call. **Not now** and
      **No thanks** were not reached by synthetic clicks (DPI-virtualised coordinates); the transitions
      behind them are unit-tested in Core and share the one code path **Rate it** exercised. Worth a
      manual click-through when the window is next open.
- [x] 7.2 `diagreviewstore` (one word — the switches take no hyphens) invokes the Store call directly
      and logs the status. In a sideload this is expected to log a failure, and that *is* the result: it
      proves the call path and the HWND initialisation exist. Verified only as far as the unpackaged
      guard, which is as far as this machine can go without a flight.
- [ ] 7.3 Walk the full localisation of the prompt in at least uk, ru and bg — the languages with
      shipping user guides.
- [ ] 7.4 Package flight through Partner Center to the developer's own account, and see the real Store
      dialog appear. A sideload has no Store licence and cannot do this, so this step is not optional and
      is not substitutable.
- [x] 7.5 `windows/RELEASING.md` gains the flight as a checklist line, with the reason, so it is not
      skipped under release pressure.
- [x] 7.6 Checked by reading `AppxManifest.xml` out of the built `.msix` rather than trusting the
      filename: **Identity 0.7.0.0**, publisher `CN=AF9BB38F-…`, languages EN-US/UK/RU/BG, activator
      CLSID present. Both version fields were bumped together (csproj `<Version>` *and* the manifest
      `Identity Version`, which `-Version` does not touch). Also confirmed the shipped binaries carry
      the feature — `uncalibrated` and `too-soon-after-first-ask` in Core, `RequestRateAndReviewAppAsync`,
      the `ms-windows-store://review/` fallback and `9MXFXL7GG3C5` in the app — and that the packaged
      flavour contains **no `msiexec`**, so the `PACKAGED` define compiled the MSI self-updater out as
      the App Certification Kit requires.

## 8. Document and release

- [x] 8.1 `docs/user-guide*.md`: a line on the review prompt and that declining it is permanent. The
      guides are the single source of truth and compile into the Help window.
- [x] 8.2 `CLAUDE.md` Windows section: the new diagnostics switches alongside `diagtoast` and friends,
      and the counters' location.
- [x] 8.3 `whats-new.md`: 0.7.0 copy in all four listing languages (en/uk/ru/bg), 800–815 characters
      each against the Store's 1,500 cap. `release-notes.md` is the **MSI** channel's text and is
      deliberately not written yet — the Store ships first, and the MSI release is a separate decision.
- [x] 8.4 Confirm the privacy posture is still accurate wherever it is stated — the app counts
      conversions locally and transmits nothing, and the Store listing should not have to be changed to
      remain true.

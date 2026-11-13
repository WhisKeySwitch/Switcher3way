using Microsoft.UI.Dispatching;
using Switcher3way.Core;

namespace Switcher3way.App;

/// <summary>
/// Counts what the app has done for this user, and — once a threshold is calibrated — asks them to
/// rate it. The decision itself lives in <see cref="StoreReview"/> in Core, where it is unit-tested
/// without the app; this class supplies the evidence, persists it, and owns the window.
///
/// <b>The automatic ask is unarmed in this release.</b> <see cref="StoreReview.Thresholds.Shipping"/>
/// is not calibrated, so <see cref="Evaluate"/> always declines with <c>uncalibrated</c>. The counters
/// still run, which is the point: they work with debug logging off, and the reason no threshold exists
/// is that the only field log available covers the days somebody switched logging on. The manual
/// <see cref="RateNow"/> path — the tray and Settings rows — is live and is this release's whole
/// user-visible feature.
///
/// Why the counting is here and not in <see cref="Engine"/>: the engine's events already arrive on the
/// UI thread through <see cref="Tray"/>, and nothing about counting may ever throw into the conversion
/// path.
/// </summary>
internal sealed class ReviewPrompt
{
    private readonly SettingsManager _settings;
    private readonly DispatcherQueue _ui;
    private readonly Func<double> _secondsSinceKeystroke;
    private readonly Func<bool> _ownWindowOpen;

    private DateTime _lastFailureUtc = DateTime.MinValue;
    private DateTime _lastUndoUtc = DateTime.MinValue;

    /// <summary>Reasons already logged this session, so a 400 ms poll cannot bury the log.</summary>
    private readonly HashSet<string> _loggedReasons = new();

    /// <summary>Counter changes not yet written to disk — see <see cref="Flush"/>.</summary>
    private bool _dirty;
    private RateWindow? _window;

    public ReviewPrompt(SettingsManager settings, DispatcherQueue ui,
                        Func<double> secondsSinceKeystroke, Func<bool> ownWindowOpen)
    {
        _settings = settings;
        _ui = ui;
        _secondsSinceKeystroke = secondsSinceKeystroke;
        _ownWindowOpen = ownWindowOpen;

        // First run: stamp the install date so an ask can require the install to be more than new. A
        // settings file from before this field exists gets stamped the first time this build runs,
        // which deliberately makes an upgrade look new rather than ancient.
        if (_settings.FirstRunUtc is null)
        {
            _settings.FirstRunUtc = DateTime.UtcNow;
            _dirty = true;
        }
    }

    // ---- counting ---------------------------------------------------------------------------

    /// <summary>
    /// A conversion reached the screen. Automatic fixes and trigger fixes both count — the field log
    /// behind the threshold found manual conversions outnumbering automatic ones 66 to 48, so counting
    /// only the automatic ones would measure well under half of what the app does for a user. What does
    /// not count is a further tap of the same candidate cycle: that is one fix being steered.
    /// </summary>
    public void NoteConverted(ConversionInfo info)
    {
        try
        {
            if (info.Source == ConversionSource.ManualCycleStep) return;

            _settings.ConversionCount++;
            var today = DateTime.UtcNow.Date;
            if (_settings.LastActiveDay?.Date != today)
            {
                // A new day: count it, and take the opportunity to persist — this is the once-a-day
                // write that keeps the counters off the per-conversion path.
                _settings.ActiveDays++;
                _settings.LastActiveDay = today;
                _dirty = true;
                Flush();
                return;
            }
            _dirty = true;
        }
        catch (Exception ex)
        {
            // Counting must never be able to disturb a conversion.
            Diagnostics.Log("review: counting failed — " + ex.Message);
        }
    }

    /// <summary>
    /// The user undid a conversion. A conversion they reversed is one the app got wrong, so it stops
    /// counting toward asking them to praise it — and the hour that follows is no time to ask at all.
    /// </summary>
    public void NoteUndone()
    {
        try
        {
            _lastUndoUtc = DateTime.UtcNow;
            if (_settings.ConversionCount > 0) { _settings.ConversionCount--; _dirty = true; }
        }
        catch (Exception ex) { Diagnostics.Log("review: undo accounting failed — " + ex.Message); }
    }

    /// <summary>A rewrite the app could not apply. Starts the same cool-off as an undo.</summary>
    public void NoteFailure() => _lastFailureUtc = DateTime.UtcNow;

    /// <summary>Persist the counters. Called on a day change, when the ask is shown, and at shutdown.</summary>
    public void Flush()
    {
        if (!_dirty) return;
        _dirty = false;
        _settings.Save();
    }

    // ---- the decision -----------------------------------------------------------------------

    private StoreReview.State CurrentState() => new(
        ConversionCount: _settings.ConversionCount,
        ActiveDays: _settings.ActiveDays,
        FirstRunUtc: _settings.FirstRunUtc,
        Ask: StoreReview.ParseState(_settings.ReviewAskState),
        AskedUtc: _settings.ReviewAskedUtc);

    private StoreReview.Context CurrentContext() => new(
        NowUtc: DateTime.UtcNow,
        IsPackaged: PackageInfo.IsPackaged,
        ConversionEnabled: _settings.EffectivelyEnabled,
        OnboardingComplete: _settings.HasCompletedOnboarding,
        // Both of these cost a Win32 call, and both are the reason the ask must not appear: asking
        // over a password field, or in a terminal where the app deliberately does nothing.
        SecureFieldFocused: SafeSecureField(),
        DeniedAppForeground: _settings.IsDeniedApp(LayoutSwitcher.Foreground().Exe),
        OwnWindowOpen: _ownWindowOpen(),
        SettingsLoadFailed: _settings.LoadFailed,
        SecondsSinceKeystroke: _secondsSinceKeystroke(),
        MinutesSinceRewriteFailure: (DateTime.UtcNow - _lastFailureUtc).TotalMinutes,
        MinutesSinceUndo: (DateTime.UtcNow - _lastUndoUtc).TotalMinutes);

    /// <summary>A probe that fails must answer "no password field", never veto by throwing.</summary>
    private static bool SafeSecureField()
    {
        try { return SecureField.IsFocusedPassword(); }
        catch (Exception ex) { Diagnostics.Log("review: secure-field probe failed — " + ex.Message); return false; }
    }

    /// <summary>
    /// Called from the tray's existing poll. Shows the ask if it is earned and the moment is right;
    /// otherwise logs why not, once per reason per session.
    ///
    /// Logging the refusal is the point rather than a nicety: a prompt that is correctly suppressed and
    /// a prompt whose code never ran leave identical evidence — nothing on screen — and this project
    /// has already lost a test session to that ambiguity.
    /// </summary>
    public void Evaluate()
    {
        try
        {
            var decision = StoreReview.ShouldAsk(CurrentState(), CurrentContext(), StoreReview.Thresholds.Shipping);
            if (!decision.Ask)
            {
                if (decision.Why is string why && _loggedReasons.Add(why))
                    Diagnostics.Log($"review: not asking — {why}");
                return;
            }
            Show(automatic: true);
        }
        catch (Exception ex)
        {
            Diagnostics.Log("review: evaluation failed — " + ex.Message);
        }
    }

    // ---- the window -------------------------------------------------------------------------

    /// <summary>The tray / Settings "Rate Switcher3way" row: the user asked, so skip every threshold.</summary>
    public void RateNow()
    {
        if (!_ui.HasThreadAccess) { _ui.TryEnqueue(RateNow); return; }
        Diagnostics.Log("review: opening the rating dialog on the user's request");
        OpenStoreReviewDialog();
    }

    /// <summary>Show the app's own ask. <paramref name="automatic"/> false means a diagnostics run.</summary>
    public void Show(bool automatic)
    {
        if (!_ui.HasThreadAccess) { _ui.TryEnqueue(() => Show(automatic)); return; }
        if (_window is not null) return;

        try
        {
            if (automatic)
            {
                // Record that it was shown before showing it. If the app dies with the window open the
                // user must not meet it again on the next launch.
                _settings.ReviewAskState = StoreReview.AskState.Asked.ToString();
                _settings.ReviewAskedUtc = DateTime.UtcNow;
                _dirty = true;
                Flush();
            }

            Diagnostics.Log($"review: showing the ask (automatic={automatic}, conversions={_settings.ConversionCount}, activeDays={_settings.ActiveDays})");
            _window = RateWindow.Show(_settings.ConversionCount, onRate: OnRate, onDefer: OnDefer, onDecline: OnDecline);
            _window.Closed += (_, _) => _window = null;
        }
        catch (Exception ex)
        {
            Diagnostics.LogAlways("review: could not show the ask — " + ex);
            _window = null;
        }
    }

    private void OnRate()
    {
        SetState(StoreReview.AfterRate(StoreReview.ParseState(_settings.ReviewAskState)), "rated");
        OpenStoreReviewDialog();   // keeps the ask window alive as the dialog's owner, then closes it
    }

    private void OnDefer() =>
        SetState(StoreReview.AfterDefer(StoreReview.ParseState(_settings.ReviewAskState)), "deferred");

    private void OnDecline() =>
        SetState(StoreReview.AfterDecline(StoreReview.ParseState(_settings.ReviewAskState)), "declined permanently");

    private void SetState(StoreReview.AskState next, string what)
    {
        _settings.ReviewAskState = next.ToString();
        _dirty = true;
        Flush();
        Diagnostics.Log($"review: user {what} — state is now {next}");
    }

    // ---- the Store ---------------------------------------------------------------------------

    /// <summary>
    /// Microsoft's in-app rating dialog. Two things about it are easy to get wrong and invisible when
    /// wrong: in a desktop app the <c>StoreContext</c> must be told which window owns the dialog, or it
    /// never appears; and it needs a Store-issued licence, so it does not work in a sideloaded package.
    /// That second point is why <c>diagreviewstore</c> exists and why the release checklist calls for a
    /// package flight — a sideload cannot stand in for this one.
    /// </summary>
    private void OpenStoreReviewDialog()
    {
        if (!PackageInfo.IsPackaged)
        {
            // Nothing to rate: an unpackaged install has no Store entitlement. The row that leads here
            // is not shown in that build, so this is a guard rather than a path.
            Diagnostics.Log("review: unpackaged build — no Store listing to rate");
            return;
        }

        var owner = _window;
        _ = RequestReviewAsync(owner);
    }

    private async Task RequestReviewAsync(RateWindow? owner)
    {
        try
        {
            var ctx = Windows.Services.Store.StoreContext.GetDefault();

            // A desktop app's StoreContext has no window of its own, and the dialog silently fails to
            // appear without one. The ask window is that owner when it is open; otherwise the Settings
            // window or any visible window of ours will do.
            IntPtr hwnd = owner is not null
                ? WinRT.Interop.WindowNative.GetWindowHandle(owner)
                : Native.GetForegroundWindow();
            if (hwnd != IntPtr.Zero) WinRT.Interop.InitializeWithWindow.Initialize(ctx, hwnd);

            var result = await ctx.RequestRateAndReviewAppAsync();
            Diagnostics.Log($"review: store dialog returned {result.Status}");
            owner?.DismissAfterStoreDialog();   // it was the dialog's owner; it has done its job

            if (result.Status is Windows.Services.Store.StoreRateAndReviewStatus.Error
                              or Windows.Services.Store.StoreRateAndReviewStatus.NetworkError)
            {
                // The dialog could not be shown. Fall back to the listing's own review page, through the
                // launcher a packaged app is permitted to use — never Process.Start, which the App
                // Certification Kit reads out of the binary whether or not it can run.
                Diagnostics.Log("review: falling back to the Store review page");
                Launch.Open($"ms-windows-store://review/?ProductId={AppIds.StoreProductId}");
            }
        }
        catch (Exception ex)
        {
            // Ungated: a user who clicked "Rate it" and saw nothing has no other way to report this.
            Diagnostics.LogAlways("review: the store dialog could not be shown — " + ex.Message);
            owner?.DismissAfterStoreDialog();
            Launch.Open($"ms-windows-store://review/?ProductId={AppIds.StoreProductId}");
        }
    }
}

/// <summary>Identifiers that must match Partner Center exactly.</summary>
internal static class AppIds
{
    /// <summary>Store ID for Switcher3way — see the Identity block in <c>Package.appxmanifest</c>.</summary>
    public const string StoreProductId = "9MXFXL7GG3C5";
}

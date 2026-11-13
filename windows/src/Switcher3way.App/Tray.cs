using Microsoft.UI.Dispatching;
using Row = Switcher3way.App.Win32Tray.Row;

namespace Switcher3way.App;

/// <summary>
/// System-tray presence: a live flag icon plus the context menu (core toggles, pause durations,
/// settings, quit), backed by <see cref="Win32Tray"/>. Owns the <see cref="Engine"/> and settings.
/// </summary>
internal sealed class Tray : IDisposable
{
    private readonly SettingsManager _settings;
    private readonly Engine _engine;
    private readonly Win32Tray _tray;
    private readonly CaretChip _chip;
    private readonly UpdateChecker _updater;
    private readonly ReviewPrompt _review;
    private readonly DispatcherQueue _dispatcher = DispatcherQueue.GetForCurrentThread();
    private readonly DispatcherQueueTimer _poll;
    private string _iconKey = "";

    /// <summary>
    /// Any window of ours on screen. The review ask must not appear on top of Settings, Help, the
    /// welcome flow or an update prompt — it would be a second dialog the user did not ask for, over
    /// one they did.
    /// </summary>
    private bool AnyOwnWindowOpen()
    {
        // Settings, Help and onboarding null themselves out on Closed, so a reference means "open".
        if (_settingsWindow is not null || _helpWindow is not null || _onboarding is not null) return true;
        // The flyout does NOT: it is created once and reused, so a reference only means it has been
        // opened at some point. Asking it whether it is visible is the difference between suppressing
        // the ask while a menu is up and suppressing it for the rest of the install's life.
        try { return _flyout is not null && _flyout.AppWindow.IsVisible; }
        catch { return false; }
    }

    public Tray()
    {
        _settings = SettingsManager.Load();
        Loc.Configure(_settings.InterfaceLanguage);

        _chip = new CaretChip();
        _engine = new Engine(_settings);

        // Notifications: a failed rewrite, and the offer to remember a word after an undo. Both arrive
        // off the UI thread — the activation callback especially, which comes from the notification
        // platform — so the settings mutation is marshalled.
        Toast.Initialize(word => _dispatcher.TryEnqueue(() => AddNeverConvert(word)));
        // Only now, because Toast.Initialize is what registers with the notification platform and
        // anything raised before it is silently discarded. Raising this ten lines earlier — next to
        // the load it reports on, where it reads better — meant the user was never told, and only a
        // packaged build showed it: unpackaged runs log the same "not registered" line for an
        // innocent reason, which hides this one completely.
        if (_settings.LoadFailed)
            Toast.ShowError(Loc.T("notify.settingsLost.title"), Loc.T("notify.settingsLost"));
        // Counts what the app has done for this user, and owns the Store review ask. The automatic ask
        // is unarmed in this release (no calibrated threshold exists yet) — the counters still run,
        // because they run with debug logging off and are what will calibrate it.
        _review = new ReviewPrompt(_settings, _dispatcher,
                                   secondsSinceKeystroke: () => _engine.SecondsSinceKeystroke,
                                   ownWindowOpen: AnyOwnWindowOpen);

        _engine.Notify += m =>
        {
            Diagnostics.Log($"notify: {m}");
            _review.NoteFailure();   // no asking for praise in the hour after a rewrite went wrong
            Toast.ShowError(m);
        };
        _engine.Undone += (original, converted) =>
        {
            _dispatcher.TryEnqueue(_review.NoteUndone);
            Toast.OfferNeverConvert(original, converted);
        };
        _engine.Hint += (title, body, chip) => ShowHint(title, body, chip);

        // Conversions are raised from the engine's worker thread — marshal to the UI thread.
        _engine.Converted += info => _dispatcher.TryEnqueue(() =>
        {
            _review.NoteConverted(info);
            if (Diagnostics.NoChip) return;
            _chip.Show(info.Original, info.Converted, _settings.TriggerLabel);
        });

        _tray = new Win32Tray(BuildMenu) { CustomMenu = ShowFlyout };
        RefreshIcon();

        _updater = new UpdateChecker(_settings, _dispatcher, Quit);
        _updater.StartSchedule();

        _engine.Start();

        // First run: explain the app and get the trigger chosen before anything else happens.
        if (!_settings.HasCompletedOnboarding) ShowOnboarding();

        // Poll the foreground layout so the flag follows it live (also picks up pause expiry).
        _poll = _dispatcher.CreateTimer();
        _poll.Interval = TimeSpan.FromMilliseconds(400);
        // The same poll carries the review ask: it needs a moment when the user is not typing, and this
        // is already the timer that watches for one. No second timer.
        _poll.Tick += (_, _) => { RefreshIcon(); _review.Evaluate(); };
        _poll.Start();
    }

    /// <summary>
    /// The trigger had nothing to convert: say so on both surfaces. The notification carries the full
    /// explanation; the chip carries a short line at the caret, and the chip is what guarantees an answer
    /// at all — it is drawn by this process, so no notification setting, Do Not Disturb, or failed
    /// notification registration can silence it. Raised from the engine's worker thread.
    /// </summary>
    internal void ShowHint(string title, string body, string chip)
    {
        Diagnostics.Log($"hint: {title} — {body}");
        Toast.ShowHint(title, body);
        _dispatcher.TryEnqueue(() => _chip.ShowMessage(chip));
    }

    // ---- Menu (rebuilt on every open, so checkmarks are live) --------------------------------
    private Row[] BuildMenu()
    {
        var rows = new List<Row>(BaseMenu());
        // Rating is a Store concept: an unpackaged install has no listing to review and the platform
        // call cannot succeed for it, so the row is absent there rather than present and broken.
        if (PackageInfo.IsPackaged)
            rows.Insert(rows.FindIndex(r => r.Text == Loc.T("menu.quit")) - 1,
                        new Row(Loc.T("menu.rate"), () => _review.RateNow()));
        return rows.ToArray();
    }

    private Row[] BaseMenu() => new[]
    {
        new Row(Loc.T("menu.autoSwitch"), () => Toggle(() => _settings.Enabled = !_settings.Enabled), _settings.Enabled),
        new Row(Loc.T("menu.autofix"), () => Toggle(() => _settings.AutoFix = !_settings.AutoFix), _settings.AutoFix),
        new Row(Loc.T("settings.perAppLayout"), () => Toggle(() => _settings.PerAppMemory = !_settings.PerAppMemory), _settings.PerAppMemory),
        new Row(_settings.IsPaused ? Loc.T("menu.resume") : Loc.T("menu.pause"), null, null, _settings.IsPaused
            ? new[] { new Row(Loc.T("menu.resume"), () => { _settings.Resume(); RefreshIcon(); }) }
            : new[]
            {
                new Row(Loc.T("menu.pause.30m"), () => DoPause(TimeSpan.FromMinutes(30))),
                new Row(Loc.T("menu.pause.1h"), () => DoPause(TimeSpan.FromHours(1))),
                new Row(Loc.T("menu.pause.untilRestart"), () => DoPause(null)),
            }),
        Row.Separator,
        new Row(Loc.T("menu.settings"), OpenSettings),
        // Help / Check for updates rejoin as those surfaces are ported.
        new Row(Loc.T("menu.help"), null, null, null, Enabled: false),
        new Row(Loc.T("menu.checkUpdates"), null, null, null, Enabled: false),
        Row.Separator,
        new Row(Loc.T("menu.quit"), Quit),
    };

    private void Toggle(Action mutate) { mutate(); _settings.Save(); RefreshIcon(); }

    private TrayFlyoutWindow? _flyout;
    /// <summary>Show the Fluent tray flyout. False → fall back to the native popup menu.</summary>
    private bool ShowFlyout()
    {
        try
        {
            _flyout ??= new TrayFlyoutWindow(_settings, RefreshIcon, OpenSettings, Quit,
                                             _updater.CheckManually, OpenHelp,
                                             rate: PackageInfo.IsPackaged ? () => _review.RateNow() : null);
            _flyout.ShowNearTray();
            return true;
        }
        catch (Exception ex)
        {
            // Also write ungated: if XAML window creation is broken, the debug log may not be usable
            // either, and this is exactly the failure we need to see in a shipped build.
            Diagnostics.LogAlways("tray flyout failed, using native menu: " + ex);
            _flyout = null;
            return false;
        }
    }

    private void DoPause(TimeSpan? d) { _settings.Pause(d); RefreshIcon(); }

    private OnboardingWindow? _onboarding;
    private void ShowOnboarding()
    {
        try
        {
            _onboarding = new OnboardingWindow(_settings, RefreshIcon);
            _onboarding.Closed += (_, _) => _onboarding = null;
            _onboarding.Activate();
            Native.SetForegroundWindow(WinRT.Interop.WindowNative.GetWindowHandle(_onboarding));
        }
        catch (Exception ex)
        {
            // Never let the welcome flow stop the app from running.
            Diagnostics.Log("onboarding failed: " + ex);
            _settings.HasCompletedOnboarding = true;
            _settings.Save();
        }
    }

    private HelpWindow? _helpWindow;
    /// <summary>Open the built-in help (single instance), in the current interface language.</summary>
    internal void OpenHelp()
    {
        if (!_dispatcher.HasThreadAccess) { _dispatcher.TryEnqueue(OpenHelp); return; }
        try
        {
            if (_helpWindow is null)
            {
                _helpWindow = new HelpWindow(Loc.Language);
                _helpWindow.Closed += (_, _) => _helpWindow = null;
            }
            _helpWindow.Activate();
            Native.SetForegroundWindow(WinRT.Interop.WindowNative.GetWindowHandle(_helpWindow));
        }
        catch (Exception ex)
        {
            Diagnostics.Log("help open failed: " + ex);
        }
    }

    /// <summary>Diagnostics only (`diagreview`): show the review ask now, bypassing every threshold.</summary>
    internal void DiagShowReviewAsk() => _review.Show(automatic: false);

    /// <summary>
    /// Diagnostics only (`diagreviewstore`): go straight to the Store's rating dialog and log its
    /// status, with no ask window in front of it.
    /// </summary>
    internal void DiagRequestStoreReview() => _review.RateNow();

    /// <summary>
    /// Diagnostics only (`diagcaret`): focus the Settings search box as a WinUI caret target and return
    /// that window's handle, so the probe can query it directly instead of the foreground window.
    /// </summary>
    internal IntPtr DiagFocusSettingsSearch()
    {
        if (_settingsWindow is null) return IntPtr.Zero;
        _settingsWindow.FocusSearchForDiagnostics();
        return WinRT.Interop.WindowNative.GetWindowHandle(_settingsWindow);
    }

    private SettingsWindow? _settingsWindow;
    internal void OpenSettings()
    {
        // WinUI windows must be created on the UI thread.
        if (!_dispatcher.HasThreadAccess) { _dispatcher.TryEnqueue(OpenSettings); return; }
        try
        {
            if (_settingsWindow is null)
            {
                _settingsWindow = new SettingsWindow(_settings, RefreshIcon,
                    onRate: PackageInfo.IsPackaged ? () => _review.RateNow() : null);
                _settingsWindow.Closed += (_, _) => _settingsWindow = null;
            }
            _settingsWindow.Activate();
            Native.SetForegroundWindow(WinRT.Interop.WindowNative.GetWindowHandle(_settingsWindow));
        }
        catch (Exception ex)
        {
            Diagnostics.LogAlways("settings open failed: " + ex);
        }
    }

    // ---- Icon -------------------------------------------------------------------------------
    private void RefreshIcon()
    {
        string lang = LayoutStatus.CurrentLang();
        bool dim = !_settings.EffectivelyEnabled;
        string key = $"{lang}:{dim}";
        string tip = dim
            ? (_settings.IsPaused ? "Switcher3way — paused" : "Switcher3way — off")
            : $"Switcher3way — {lang.ToUpperInvariant()}";
        if (key != _iconKey)
        {
            _tray.SetIcon(FlagIcon.Make(lang, dim).Handle, tip);
            _iconKey = key;
        }
    }

    private void Quit()
    {
        Dispose();
        Microsoft.UI.Xaml.Application.Current.Exit();
    }

    /// <summary>
    /// Accept the notification's offer: suppress this word in future. Runs on the UI thread (the
    /// activation callback marshals here), so it can touch settings and the open Settings window safely.
    /// </summary>
    private void AddNeverConvert(string word)
    {
        if (_settings.NeverConvertWords.Any(w => string.Equals(w, word, StringComparison.OrdinalIgnoreCase)))
            return;
        _settings.NeverConvertWords.Add(word);
        _settings.Save();
        RefreshIcon();
        _settingsWindow?.ReloadExceptions();   // if it happens to be open, show the new row
    }

    public void Dispose()
    {
        _poll.Stop();
        _review.Flush();   // the counters are kept in memory between day changes — don't lose the session
        _engine.Stop();
        _chip.Dispose();
        _tray.Dispose();
        Toast.Shutdown();
    }
}

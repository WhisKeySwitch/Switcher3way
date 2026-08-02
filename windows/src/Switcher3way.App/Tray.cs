using Microsoft.UI.Dispatching;
using Row = Switcher3way.App.Win32Tray.Row;

namespace Switcher3way.App;

/// <summary>
/// System-tray presence: a live flag icon plus the context menu (core toggles, pause durations,
/// settings, quit), backed by <see cref="Win32Tray"/>. Owns the <see cref="Engine"/> and settings.
/// Replaces the WinForms TrayApp. Help/Updates rejoin the menu as those surfaces are ported.
/// </summary>
internal sealed class Tray : IDisposable
{
    private readonly SettingsManager _settings;
    private readonly Engine _engine;
    private readonly Win32Tray _tray;
    private readonly CaretChip _chip;
    private readonly DispatcherQueue _dispatcher = DispatcherQueue.GetForCurrentThread();
    private readonly DispatcherQueueTimer _poll;
    private string _iconKey = "";

    public Tray()
    {
        _settings = SettingsManager.Load();
        Loc.Configure(_settings.InterfaceLanguage);

        _chip = new CaretChip();
        _engine = new Engine(_settings);
        _engine.Notify += m => Diagnostics.Log($"notify: {m}"); // TODO: error toast (1g)
        // Conversions are raised from the engine's worker thread — marshal to the UI thread.
        _engine.Converted += info => _dispatcher.TryEnqueue(() =>
            _chip.Show(info.Original, info.Converted, _settings.TriggerLabel));

        _tray = new Win32Tray(BuildMenu);
        RefreshIcon();

        _engine.Start();

        // Poll the foreground layout so the flag follows it live (also picks up pause expiry).
        _poll = _dispatcher.CreateTimer();
        _poll.Interval = TimeSpan.FromMilliseconds(400);
        _poll.Tick += (_, _) => RefreshIcon();
        _poll.Start();
    }

    // ---- Menu (rebuilt on every open, so checkmarks are live) --------------------------------
    private Row[] BuildMenu() => new[]
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

    private void DoPause(TimeSpan? d) { _settings.Pause(d); RefreshIcon(); }

    private SettingsWindow? _settingsWindow;
    internal void OpenSettings()
    {
        // WinUI windows must be created on the UI thread.
        if (!_dispatcher.HasThreadAccess) { _dispatcher.TryEnqueue(OpenSettings); return; }
        try
        {
            if (_settingsWindow is null)
            {
                _settingsWindow = new SettingsWindow(_settings, RefreshIcon);
                _settingsWindow.Closed += (_, _) => _settingsWindow = null;
            }
            _settingsWindow.Activate();
            Native.SetForegroundWindow(WinRT.Interop.WindowNative.GetWindowHandle(_settingsWindow));
        }
        catch (Exception ex)
        {
            Diagnostics.Log("settings open failed: " + ex);
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

    public void Dispose()
    {
        _poll.Stop();
        _engine.Stop();
        _chip.Dispose();
        _tray.Dispose();
    }
}

using System.Globalization;
using H.NotifyIcon;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml.Controls;

namespace Switcher3way.App;

/// <summary>
/// System-tray presence (WinUI 3, via H.NotifyIcon): a live flag icon + a Fluent context flyout with
/// the core toggles, pause durations, and quit. Owns the <see cref="Engine"/> and settings. Replaces
/// the WinForms TrayApp. Settings/Help/Updates rejoin the flyout as those surfaces are ported.
/// </summary>
internal sealed class Tray : IDisposable
{
    private readonly SettingsManager _settings;
    private readonly Engine _engine;
    private readonly TaskbarIcon _icon;
    private readonly DispatcherQueueTimer _poll;

    private ToggleMenuFlyoutItem _enableItem = null!, _autoFixItem = null!, _perAppItem = null!;
    private string _iconKey = "";

    public Tray()
    {
        _settings = SettingsManager.Load();
        Loc.Configure(_settings.InterfaceLanguage);

        _engine = new Engine(_settings);
        _engine.Notify += m => Diagnostics.Log($"notify: {m}"); // TODO(feedback phase): toast

        _icon = new TaskbarIcon { ToolTipText = "Switcher3way", ContextFlyout = BuildMenu() };
        RefreshIcon();
        _icon.ForceCreate();

        _engine.Start();
        UpdateUi();

        // Poll the foreground layout so the flag follows it live (also picks up pause expiry).
        _poll = DispatcherQueue.GetForCurrentThread().CreateTimer();
        _poll.Interval = TimeSpan.FromMilliseconds(400);
        _poll.Tick += (_, _) => RefreshIcon();
        _poll.Start();
    }

    // ---- Menu -------------------------------------------------------------------------------
    private MenuFlyout BuildMenu()
    {
        var m = new MenuFlyout();

        _enableItem = Toggle(Loc.T("menu.autoSwitch"), () => _settings.Enabled = !_settings.Enabled);
        _autoFixItem = Toggle(Loc.T("menu.autofix"), () => _settings.AutoFix = !_settings.AutoFix);
        _perAppItem = Toggle(Loc.T("settings.perAppLayout"), () => _settings.PerAppMemory = !_settings.PerAppMemory);
        m.Items.Add(_enableItem);
        m.Items.Add(_autoFixItem);
        m.Items.Add(_perAppItem);

        var pause = new MenuFlyoutSubItem { Text = Loc.T("menu.pause") };
        pause.Items.Add(Item(Loc.T("menu.pause.30m"), () => DoPause(TimeSpan.FromMinutes(30))));
        pause.Items.Add(Item(Loc.T("menu.pause.1h"), () => DoPause(TimeSpan.FromHours(1))));
        pause.Items.Add(Item(Loc.T("menu.pause.untilRestart"), () => DoPause(null)));
        pause.Items.Add(new MenuFlyoutSeparator());
        pause.Items.Add(Item(Loc.T("menu.resume"), () => { _settings.Resume(); UpdateUi(); }));
        m.Items.Add(pause);

        m.Items.Add(new MenuFlyoutSeparator());
        m.Items.Add(Item(Loc.T("menu.settings"), OpenSettings));
        // Help / Check for updates rejoin as those surfaces are ported (disabled for now).
        m.Items.Add(new MenuFlyoutItem { Text = Loc.T("menu.help"), IsEnabled = false });
        m.Items.Add(new MenuFlyoutItem { Text = Loc.T("menu.checkUpdates"), IsEnabled = false });
        m.Items.Add(new MenuFlyoutSeparator());
        m.Items.Add(Item(Loc.T("menu.quit"), Quit));
        return m;
    }

    private ToggleMenuFlyoutItem Toggle(string text, Action mutate)
    {
        var it = new ToggleMenuFlyoutItem { Text = text };
        it.Click += (_, _) => { mutate(); _settings.Save(); UpdateUi(); };
        return it;
    }

    private static MenuFlyoutItem Item(string text, Action action)
    {
        var it = new MenuFlyoutItem { Text = text };
        it.Click += (_, _) => action();
        return it;
    }

    private void DoPause(TimeSpan? d) { _settings.Pause(d); UpdateUi(); }

    private SettingsWindow? _settingsWindow;
    internal void OpenSettings()
    {
        try
        {
            if (_settingsWindow is null)
            {
                _settingsWindow = new SettingsWindow(_settings, UpdateUi);
                _settingsWindow.Closed += (_, _) => _settingsWindow = null;
            }
            _settingsWindow.Activate();
            // A window created from a tray-flyout click can't grab foreground on its own — force it,
            // or it opens behind everything and looks like nothing happened.
            Native.SetForegroundWindow(WinRT.Interop.WindowNative.GetWindowHandle(_settingsWindow));
        }
        catch (Exception ex)
        {
            Diagnostics.Log("settings open failed: " + ex);
        }
    }

    private void UpdateUi()
    {
        _enableItem.IsChecked = _settings.Enabled;
        _autoFixItem.IsChecked = _settings.AutoFix;
        _perAppItem.IsChecked = _settings.PerAppMemory;
        RefreshIcon();
    }

    // ---- Icon -------------------------------------------------------------------------------
    private void RefreshIcon()
    {
        string lang = CurrentLang();
        bool dim = !_settings.EffectivelyEnabled;
        string key = $"{lang}:{dim}";
        if (key != _iconKey) { _icon.Icon = FlagIcon.Make(lang, dim); _iconKey = key; }
        _icon.ToolTipText = dim
            ? (_settings.IsPaused ? "Switcher3way — paused" : "Switcher3way — off")
            : $"Switcher3way — {lang.ToUpperInvariant()}";
    }

    /// <summary>The foreground app's current layout language (en/ru/uk…), per-thread on Windows.</summary>
    private static string CurrentLang()
    {
        var hwnd = Native.GetForegroundWindow();
        uint tid = Native.GetWindowThreadProcessId(hwnd, out _);
        int langId = (int)((long)Native.GetKeyboardLayout(tid) & 0xFFFF);
        try { return CultureInfo.GetCultureInfo(langId).TwoLetterISOLanguageName; }
        catch (CultureNotFoundException) { return "?"; }
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
        _icon.Dispose();
    }
}

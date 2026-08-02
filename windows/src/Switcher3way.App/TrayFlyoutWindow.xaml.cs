using System.Runtime.InteropServices;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Windows.Graphics;

namespace Switcher3way.App;

/// <summary>
/// The tray menu as a Fluent flyout: a small borderless always-on-top window with real WinUI
/// controls (toggle switches, buttons), shown next to the notification area and dismissed when it
/// loses focus.
///
/// Replaces the native <c>TrackPopupMenu</c>, which routed clicks reliably but looked like a
/// Windows-95-era menu. A real window is used rather than a XAML flyout because a tray-only app has
/// no XamlRoot to host one — that was what made the earlier flyout's clicks go nowhere.
/// </summary>
public sealed partial class TrayFlyoutWindow : Window
{
    private const int Width = 290;

    private readonly SettingsManager _s;
    private readonly Action _changed;      // settings mutated → refresh tray icon
    private readonly Action _openSettings;
    private readonly Action _quit;
    private readonly Action _checkUpdates;
    private readonly Action _openHelp;
    private bool _loading;

    public TrayFlyoutWindow(SettingsManager s, Action changed, Action openSettings, Action quit,
                            Action checkUpdates, Action openHelp)
    {
        _s = s;
        _changed = changed;
        _openSettings = openSettings;
        _quit = quit;
        _checkUpdates = checkUpdates;
        _openHelp = openHelp;
        this.InitializeComponent();

        // Borderless, no taskbar entry, always on top — a context-menu-shaped window.
        var presenter = OverlappedPresenter.CreateForContextMenu();
        presenter.IsAlwaysOnTop = true;
        AppWindow.SetPresenter(presenter);
        AppWindow.IsShownInSwitchers = false;

        Activated += (_, e) =>
        {
            if (e.WindowActivationState == WindowActivationState.Deactivated) AppWindow.Hide();
        };
    }

    /// <summary>Refresh the contents from settings and show the flyout next to the notification area.</summary>
    public void ShowNearTray()
    {
        Refresh();

        // Size to the content, then place it inside the work area near the cursor (i.e. the tray).
        Root.Measure(new global::Windows.Foundation.Size(Width, double.PositiveInfinity));
        int h = (int)Math.Ceiling(Root.DesiredSize.Height) + 8;
        double scale = AppWindow.Id.Value == 0 ? 1 : GetDpiForWindow(Hwnd()) / 96.0;
        int w = (int)(Width * scale), ph = (int)(h * scale);

        GetCursorPos(out POINT cur);
        var area = DisplayArea.GetFromPoint(new PointInt32(cur.x, cur.y), DisplayAreaFallback.Nearest).WorkArea;
        int x = Math.Clamp(cur.x - w / 2, area.X + 8, area.X + area.Width - w - 8);
        int y = Math.Max(area.Y + 8, area.Y + area.Height - ph - 8);   // sit above the taskbar

        AppWindow.MoveAndResize(new RectInt32(x, y, w, ph));
        AppWindow.Show();
        SetForegroundWindow(Hwnd());   // a tray-invoked window can't take focus on its own
    }

    private IntPtr Hwnd() => WinRT.Interop.WindowNative.GetWindowHandle(this);

    private void Refresh()
    {
        _loading = true;

        string lang = LayoutStatus.CurrentLang();
        Flag.Source = FlagIcon.Image(lang);
        LayoutName.Text = LayoutStatus.LangName(lang);
        StatusSub.Text = _s.IsPaused
            ? "Paused"
            : _s.Enabled
                ? $"{(_s.AutoFix ? "Auto-fix on" : "Auto-fix off")} · {_s.TriggerLabel} to convert"
                : "Off";

        T_Enable.Text = Loc.T("menu.autoSwitch");
        T_AutoFix.Text = Loc.T("menu.autofix");
        T_PerApp.Text = Loc.T("settings.perAppLayout");
        T_Pause.Text = Loc.T("menu.pause");
        T_Resume.Text = Loc.T("menu.resume");
        T_Settings.Text = Loc.T("menu.settings");
        T_Help.Text = Loc.T("menu.help");
        T_Updates.Text = Loc.T("menu.checkUpdates");
        T_Quit.Text = Loc.T("menu.quit");
        PauseRestart.Content = Loc.T("menu.pause.untilRestart");

        EnableSwitch.IsOn = _s.Enabled;
        AutoFixSwitch.IsOn = _s.AutoFix;
        PerAppSwitch.IsOn = _s.PerAppMemory;

        // While paused, offer Resume instead of the durations.
        bool paused = _s.IsPaused;
        T_Pause.Visibility = paused ? Visibility.Collapsed : Visibility.Visible;
        PauseButtons.Visibility = paused ? Visibility.Collapsed : Visibility.Visible;
        ResumeButton.Visibility = paused ? Visibility.Visible : Visibility.Collapsed;

        _loading = false;
    }

    private void Commit() { _s.Save(); _changed(); Refresh(); }

    private void EnableSwitch_Toggled(object s, RoutedEventArgs e) { if (_loading) return; _s.Enabled = EnableSwitch.IsOn; Commit(); }
    private void AutoFixSwitch_Toggled(object s, RoutedEventArgs e) { if (_loading) return; _s.AutoFix = AutoFixSwitch.IsOn; Commit(); }
    private void PerAppSwitch_Toggled(object s, RoutedEventArgs e) { if (_loading) return; _s.PerAppMemory = PerAppSwitch.IsOn; Commit(); }

    private void Pause30_Click(object s, RoutedEventArgs e) => Pause(TimeSpan.FromMinutes(30));
    private void Pause60_Click(object s, RoutedEventArgs e) => Pause(TimeSpan.FromHours(1));
    private void PauseRestart_Click(object s, RoutedEventArgs e) => Pause(null);
    private void Pause(TimeSpan? d) { _s.Pause(d); _changed(); AppWindow.Hide(); }
    private void Resume_Click(object s, RoutedEventArgs e) { _s.Resume(); _changed(); AppWindow.Hide(); }

    private void Settings_Click(object s, RoutedEventArgs e) { AppWindow.Hide(); _openSettings(); }
    private void Help_Click(object s, RoutedEventArgs e) { AppWindow.Hide(); _openHelp(); }
    private void Updates_Click(object s, RoutedEventArgs e) { AppWindow.Hide(); _checkUpdates(); }
    private void Quit_Click(object s, RoutedEventArgs e) { AppWindow.Hide(); _quit(); }

    [StructLayout(LayoutKind.Sequential)] private struct POINT { public int x, y; }
    [DllImport("user32.dll")] private static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern uint GetDpiForWindow(IntPtr hWnd);
}

using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.Graphics;

namespace Switcher3way.App;

/// <summary>
/// Settings window (WinUI 3) — tabbed shell + General tab, immediate-apply. Each control writes
/// straight to <see cref="SettingsManager"/> and calls Save(); the tray is notified so surfaces stay
/// in sync. Auto-fix / Advanced / About are placeholders until ported.
/// </summary>
public sealed partial class SettingsWindow : Window
{
    private sealed record TriggerKey(string Name, int Vk, bool Double) { public override string ToString() => Name; }
    private static readonly TriggerKey[] Triggers =
    {
        new("F8", 0x77, false), new("F9", 0x78, false), new("F10", 0x79, false), new("F11", 0x7A, false),
        new("F12", 0x7B, false), new("Pause/Break", 0x13, false), new("Scroll Lock", 0x91, false),
        new("Right Ctrl", 0xA3, false), new("Double Shift", 0x10, true), new("Double Ctrl", 0x11, true),
        new("Double Alt", 0x12, true),
    };

    private sealed record Lang(string Code, string Name) { public override string ToString() => Name; }
    private static readonly Lang[] Languages =
    {
        new("", "System default — English"), new("en", "English"), new("uk", "Українська"),
        new("ru", "Русский"), new("be", "Беларуская"), new("de", "Deutsch"), new("fr", "Français"),
        new("es", "Español"), new("pt", "Português"), new("pl", "Polski"), new("zh", "中文"),
        new("ja", "日本語"), new("ko", "한국어"), new("el", "Ελληνικά"), new("bg", "Български"),
        new("hy", "Հայերեն"), new("ka", "ქართული"),
    };

    private readonly SettingsManager _s;
    private readonly Action _onChanged;
    private bool _loading;

    public SettingsWindow(SettingsManager s, Action onChanged)
    {
        _s = s;
        _onChanged = onChanged;
        this.InitializeComponent();
        AppWindow.Resize(new SizeInt32(620, 660));

        _loading = true;
        EnableToggle.IsOn = _s.Enabled;
        PerAppToggle.IsOn = _s.PerAppMemory;
        StartupToggle.IsOn = StartupShortcut.IsEnabled;

        foreach (var t in Triggers) TriggerCombo.Items.Add(t);
        TriggerCombo.SelectedItem = Triggers.FirstOrDefault(t => t.Vk == _s.TriggerKey && t.Double == _s.TriggerDoubleTap) ?? Triggers[1];
        foreach (var l in Languages) LanguageCombo.Items.Add(l);
        LanguageCombo.SelectedItem = Languages.FirstOrDefault(l => l.Code == _s.InterfaceLanguage) ?? Languages[0];
        _loading = false;

        RefreshStatus();
    }

    private void RefreshStatus()
    {
        var lang = LayoutStatus.CurrentLang();
        int count = new Win32LayoutCatalog().InstalledLayouts().Count;
        StatusLine.Text = $"{LayoutStatus.LangName(lang)} — current layout";
        StatusSub.Text = $"{count} layouts installed";
        bool on = _s.EffectivelyEnabled;
        StatusPillText.Text = _s.IsPaused ? "Paused" : (on ? "Active" : "Off");
    }

    // ---- immediate-apply handlers ----------------------------------------------------------
    private void Commit()
    {
        _s.Save();
        _onChanged();
        RefreshStatus();
    }

    private void EnableToggle_Toggled(object s, RoutedEventArgs e) { if (_loading) return; _s.Enabled = EnableToggle.IsOn; Commit(); }
    private void PerAppToggle_Toggled(object s, RoutedEventArgs e) { if (_loading) return; _s.PerAppMemory = PerAppToggle.IsOn; Commit(); }
    private void StartupToggle_Toggled(object s, RoutedEventArgs e) { if (_loading) return; StartupShortcut.Set(StartupToggle.IsOn); }

    private void TriggerCombo_SelectionChanged(object s, SelectionChangedEventArgs e)
    {
        if (_loading || TriggerCombo.SelectedItem is not TriggerKey t) return;
        _s.TriggerKey = t.Vk;
        _s.TriggerDoubleTap = t.Double;
        Commit();
    }

    private void LanguageCombo_SelectionChanged(object s, SelectionChangedEventArgs e)
    {
        if (_loading || LanguageCombo.SelectedItem is not Lang l) return;
        _s.InterfaceLanguage = l.Code;
        Loc.Configure(l.Code);
        Commit();
    }

    private void Tabs_SelectionChanged(SelectorBar sender, SelectorBarSelectionChangedEventArgs args)
    {
        GeneralPanel.Visibility = Tabs.SelectedItem == TabGeneral ? Visibility.Visible : Visibility.Collapsed;
        AutoFixPanel.Visibility = Tabs.SelectedItem == TabAutoFix ? Visibility.Visible : Visibility.Collapsed;
        AdvancedPanel.Visibility = Tabs.SelectedItem == TabAdvanced ? Visibility.Visible : Visibility.Collapsed;
        AboutPanel.Visibility = Tabs.SelectedItem == TabAbout ? Visibility.Visible : Visibility.Collapsed;
    }

    private void Close_Click(object s, RoutedEventArgs e) => this.Close();
}

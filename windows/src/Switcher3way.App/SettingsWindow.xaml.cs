using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
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

        AutoFixToggle.IsOn = _s.AutoFix;
        foreach (var a in AmbLangs) AmbiguousCombo.Items.Add(a);
        AmbiguousCombo.SelectedItem = AmbLangs.FirstOrDefault(a => a.Value == _s.AmbiguousLang) ?? AmbLangs[0];
        UpdatesToggle.IsOn = _s.CheckForUpdates;
        DebugToggle.IsOn = _s.DebugLog;
        LogPathText.Text = Diagnostics.FilePath;

        var v = typeof(SettingsWindow).Assembly.GetName().Version;
        AboutVersion.Text = $"Version {v?.Major}.{v?.Minor}.{v?.Build} — Windows preview";
        if (Environment.ProcessPath is string exe) AboutIcon.Source = AppInfo.Icon(exe);
        _loading = false;

        RefreshStatus();
        RefreshExceptions();
    }

    private sealed record AmbLang(string Value, string Name) { public override string ToString() => Name; }
    private static readonly AmbLang[] AmbLangs =
    {
        new("uk", "Українська"), new("ru", "Русский"), new("off", "Do not convert"),
    };

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
        ApplyLanguage();   // update this window's strings in place
    }

    /// <summary>
    /// Re-apply every localized string to the live UI. Used after an interface-language change:
    /// closing and re-creating the window to reload the XAML crashed WinUI natively (access
    /// violation in Microsoft.UI.Xaml.dll), so the strings are swapped in place instead.
    /// </summary>
    private void ApplyLanguage()
    {
        TabGeneral.Text = Loc.T("settings.tab.general");
        TabAutoFix.Text = Loc.T("settings.tab.autofix");
        TabAdvanced.Text = Loc.T("settings.tab.advanced");
        TabAbout.Text = Loc.T("settings.tab.about");

        T_Enable.Text = Loc.T("settings.autoSwitch");
        T_PerApp.Text = Loc.T("settings.perAppLayout");
        T_Trigger.Text = Loc.T("settings.trigger");
        T_Language.Text = Loc.T("settings.language");
        T_AutoFix.Text = Loc.T("settings.autofix.title");
        T_Amb.Text = Loc.T("settings.autofix.ambiguousLang");
        T_AmbHint.Text = Loc.T("settings.autofix.ambiguousLang.hint");
        T_Exceptions.Text = Loc.T("settings.group.exceptions");
        T_Updates.Text = Loc.T("settings.checkUpdates");
        T_Debug.Text = Loc.T("settings.debugLog");
        T_Tagline.Text = Loc.T("win.tagline");
        B_OpenLog.Content = Loc.T("win.openLog");
        ExcSearch.PlaceholderText = Loc.T("settings.exceptions.search");
        AddWordButton.Content = Loc.T("common.add");

        // Rebuild the "System default" entry and the rows (their labels are localized too).
        RefreshExceptions();
    }

    private void Tabs_SelectionChanged(SelectorBar sender, SelectorBarSelectionChangedEventArgs args)
    {
        GeneralPanel.Visibility = Tabs.SelectedItem == TabGeneral ? Visibility.Visible : Visibility.Collapsed;
        AutoFixPanel.Visibility = Tabs.SelectedItem == TabAutoFix ? Visibility.Visible : Visibility.Collapsed;
        AdvancedPanel.Visibility = Tabs.SelectedItem == TabAdvanced ? Visibility.Visible : Visibility.Collapsed;
        AboutPanel.Visibility = Tabs.SelectedItem == TabAbout ? Visibility.Visible : Visibility.Collapsed;
    }

    private void Close_Click(object s, RoutedEventArgs e) => this.Close();

    // ---- Auto-fix ---------------------------------------------------------------------------
    private void AutoFixToggle_Toggled(object s, RoutedEventArgs e) { if (_loading) return; _s.AutoFix = AutoFixToggle.IsOn; Commit(); }

    private void AmbiguousCombo_SelectionChanged(object s, SelectionChangedEventArgs e)
    {
        if (_loading || AmbiguousCombo.SelectedItem is not AmbLang a) return;
        _s.AmbiguousLang = a.Value;
        Commit();
    }

    // ---- Advanced ---------------------------------------------------------------------------
    private void UpdatesToggle_Toggled(object s, RoutedEventArgs e) { if (_loading) return; _s.CheckForUpdates = UpdatesToggle.IsOn; Commit(); }
    private void DebugToggle_Toggled(object s, RoutedEventArgs e) { if (_loading) return; _s.DebugLog = DebugToggle.IsOn; Commit(); }

    private void OpenLog_Click(object s, RoutedEventArgs e) => Launch.OpenFolder(Diagnostics.Dir);

    // ---- Exceptions ------------------------------------------------------------------------
    /// <summary>0 = Apps, 1 = Never convert, 2 = Always convert.</summary>
    private int SegIndex =>
        ExcSeg.SelectedItem == SegNever ? 1 : ExcSeg.SelectedItem == SegAlways ? 2 : 0;

    private List<string> CurrentList => SegIndex switch
    {
        1 => _s.NeverConvertWords,
        2 => _s.AlwaysConvertWords,
        _ => _s.DeniedApps,
    };

    private void RefreshExceptions()
    {
        // Live counts on the segments.
        SegApps.Text = $"{Loc.T("settings.exceptions.seg.apps")}  {SettingsManager.ProtectedApps.Length + _s.DeniedApps.Count}";
        SegNever.Text = $"{Loc.T("settings.exceptions.seg.never")}  {_s.NeverConvertWords.Count}";
        SegAlways.Text = $"{Loc.T("settings.exceptions.seg.always")}  {_s.AlwaysConvertWords.Count}";

        string q = ExcSearch.Text.Trim();
        bool Match(string v) => q.Length == 0 || v.Contains(q, StringComparison.OrdinalIgnoreCase);

        bool apps = SegIndex == 0;
        var protectedRows = new List<ExceptionRow>();
        var userRows = new List<ExceptionRow>();

        if (apps)
        {
            foreach (var exe in SettingsManager.ProtectedApps.Where(Match))
                protectedRows.Add(AppRow(exe, isProtected: true));
            foreach (var exe in _s.DeniedApps.Where(Match))
                userRows.Add(AppRow(exe, isProtected: false));
        }
        else
        {
            foreach (var w in CurrentList.Where(Match))
                userRows.Add(new ExceptionRow { Value = w, Display = w });
        }

        ProtectedHeader.Visibility = apps && protectedRows.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
        ProtectedList.ItemsSource = protectedRows;
        UserHeader.Visibility = apps && userRows.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
        UserList.ItemsSource = userRows;

        // Empty states.
        if (userRows.Count == 0)
        {
            EmptyNote.Visibility = Visibility.Visible;
            EmptyNote.Text = apps
                ? "No apps added yet."
                : "Nothing here yet — undo a fix with the trigger key to add a word.";
        }
        else EmptyNote.Visibility = Visibility.Collapsed;

        // Footer swaps between "add app" and "add word".
        AddAppButton.Visibility = apps ? Visibility.Visible : Visibility.Collapsed;
        AddAppHint.Visibility = apps ? Visibility.Visible : Visibility.Collapsed;
        AddWordBox.Visibility = apps ? Visibility.Collapsed : Visibility.Visible;
        AddWordButton.Visibility = apps ? Visibility.Collapsed : Visibility.Visible;
    }

    /// <summary>A row for an excluded app — real icon and friendly name when the app is running.</summary>
    private static ExceptionRow AppRow(string exe, bool isProtected)
    {
        var path = AppInfo.PathForExeName(exe);
        return new ExceptionRow
        {
            Value = exe,
            Display = path is null ? System.IO.Path.GetFileNameWithoutExtension(exe) : AppInfo.FriendlyName(path),
            Sub = exe,
            Icon = path is null ? null : AppInfo.Icon(path),
            IsProtected = isProtected,
        };
    }

    private void ExcSeg_SelectionChanged(SelectorBar sender, SelectorBarSelectionChangedEventArgs args) => RefreshExceptions();
    private void ExcSearch_TextChanged(object s, TextChangedEventArgs e) => RefreshExceptions();

    private void RemoveRow_Click(object s, RoutedEventArgs e)
    {
        if (s is not Button b || b.Tag is not string value) return;
        CurrentList.RemoveAll(x => string.Equals(x, value, StringComparison.OrdinalIgnoreCase));
        Commit();
        RefreshExceptions();
    }

    private void AddWord_Click(object s, RoutedEventArgs e) => AddWord();
    private void AddWordBox_KeyDown(object s, KeyRoutedEventArgs e)
    {
        if (e.Key == Windows.System.VirtualKey.Enter) { AddWord(); e.Handled = true; }
    }

    private void AddWord()
    {
        var v = AddWordBox.Text.Trim();
        if (v.Length == 0) return;
        if (!CurrentList.Any(x => string.Equals(x, v, StringComparison.OrdinalIgnoreCase))) CurrentList.Add(v);
        AddWordBox.Text = "";
        Commit();
        RefreshExceptions();
    }

    /// <summary>The Add-an-app picker: pick from running apps instead of typing an .exe name.</summary>
    private async void AddApp_Click(object s, RoutedEventArgs e)
    {
        var listed = SettingsManager.ProtectedApps.Concat(_s.DeniedApps);
        var rows = AppInfo.RunningApps(listed)
            .Select(a => new ExceptionRow { Value = a.ExeName, Display = a.FriendlyName, Sub = a.ExeName, Icon = AppInfo.Icon(a.Path) })
            .ToList();

        var list = new ListView
        {
            ItemsSource = rows,
            SelectionMode = ListViewSelectionMode.Multiple,
            ItemTemplate = (DataTemplate)((FrameworkElement)Content).Resources["PickerTemplate"],
            MaxHeight = 320,
        };
        var dialog = new ContentDialog
        {
            XamlRoot = Content.XamlRoot,
            Title = "Add an app",
            Content = new StackPanel
            {
                Spacing = 10,
                Children =
                {
                    new TextBlock { Text = "Auto-fix stays off in the apps you pick.", FontSize = 13, Opacity = 0.8 },
                    list,
                },
            },
            PrimaryButtonText = "Add",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Primary,
        };
        list.SelectionChanged += (_, _) =>
            dialog.PrimaryButtonText = list.SelectedItems.Count switch
            {
                0 => "Add",
                1 => "Add 1 app",
                var n => $"Add {n} apps",
            };

        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;
        foreach (var row in list.SelectedItems.OfType<ExceptionRow>())
        {
            var exe = row.Value.ToLowerInvariant();
            if (!_s.DeniedApps.Any(x => string.Equals(x, exe, StringComparison.OrdinalIgnoreCase)))
                _s.DeniedApps.Add(exe);
        }
        Commit();
        RefreshExceptions();
    }
}

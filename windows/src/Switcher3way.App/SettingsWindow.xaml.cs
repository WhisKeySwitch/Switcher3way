using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Windows.ApplicationModel.DataTransfer;
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
    // Ordered by how well they work in practice: the recommended three first, the rest after.
    private static readonly TriggerKey[] Triggers =
    {
        new("Double Ctrl", 0x11, true), new("Pause/Break", 0x13, false), new("F9", 0x78, false),
        new("Double Shift", 0x10, true), new("Double Alt", 0x12, true), new("Right Ctrl", 0xA3, false),
        new("Scroll Lock", 0x91, false), new("F8", 0x77, false), new("F10", 0x79, false),
        new("F11", 0x7A, false), new("F12", 0x7B, false),
    };

    private sealed record Lang(string Code, string Name) { public override string ToString() => Name; }
    /// <summary>
    /// Language names stay in their own language. Anything that isn't fully translated yet is labelled
    /// as partial rather than quietly serving English — see <see cref="Loc.IsComplete"/>.
    /// </summary>
    private static Lang[] BuildLanguages() => LanguageNames
        .Select(l => Loc.IsComplete(l.Code) ? l : l with { Name = $"{l.Name} — {Loc.T("settings.language.partial")}" })
        .ToArray();

    private static readonly Lang[] LanguageNames =
    {
        new("", "System default"), new("en", "English"), new("uk", "Українська"),
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
        TriggerCombo.SelectedItem = Triggers.FirstOrDefault(t => t.Vk == _s.TriggerKey && t.Double == _s.TriggerDoubleTap)
                                    ?? Triggers[0];   // the recommended default
        RebuildLanguageCombo();

        AutoFixToggle.IsOn = _s.AutoFix;
        RebuildAmbiguousCombo();
        UpdatesToggle.IsOn = _s.CheckForUpdates;
        DebugToggle.IsOn = _s.DebugLog;
        LogPathText.Text = Diagnostics.FilePath;

        if (Environment.ProcessPath is string exe) AboutIcon.Source = AppInfo.Icon(exe);
        _loading = false;

        // One code path for every string in this window, on first open as well as on a language
        // change — otherwise the two drift and half the window stays in English.
        ApplyLanguage();
    }

    private sealed record AmbLang(string Value, string Name) { public override string ToString() => Name; }
    /// <summary>Built on demand: the language names stay as they are, "Do not convert" is localized.</summary>
    private static AmbLang[] AmbLangs() => new AmbLang[]
    {
        new("uk", "Українська"), new("ru", "Русский"), new("off", Loc.T("settings.autofix.ambiguousLang.off")),
    };

    private void RefreshStatus()
    {
        var lang = LayoutStatus.CurrentLang();
        int count = new Win32LayoutCatalog().InstalledLayouts().Count;
        StatusLine.Text = Loc.Tf("settings.status.currentLayout", LayoutStatus.LangName(lang));
        StatusSub.Text = Loc.Tf("settings.status.layoutsInstalled", count);
        bool on = _s.EffectivelyEnabled;
        StatusPillText.Text = _s.IsPaused ? Loc.T("settings.status.paused")
                                          : (on ? Loc.T("settings.status.active") : Loc.T("settings.status.off"));
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

        // Everything below used to be hard-coded English in the XAML, so switching the interface
        // language left most of this window untranslated.
        Title = Loc.T("settings.window.title");
        D_Enable.Text = Loc.T("settings.autoSwitch.desc");
        D_PerApp.Text = Loc.T("settings.perAppLayout.desc");
        T_Startup.Text = Loc.T("settings.startup");
        D_Startup.Text = Loc.T("settings.startup.desc");
        H_Trigger.Text = Loc.T("settings.group.trigger");
        D_Trigger.Text = Loc.T("settings.trigger.desc");
        D_Language.Text = Loc.T("settings.language.desc");
        D_AutoFix.Text = Loc.T("settings.autofix.desc");
        D_Exceptions.Text = Loc.T("settings.exceptions.desc");
        T_ProtectedHeader.Text = Loc.T("settings.exceptions.protectedHeader");
        T_UserHeader.Text = Loc.T("settings.exceptions.userHeader");
        AddAppButton.Content = Loc.T("settings.exceptions.addApp");
        AddAppHint.Text = Loc.T("settings.exceptions.addAppHint");
        AddWordBox.PlaceholderText = Loc.T("settings.exceptions.addWord");
        D_Updates.Text = Loc.T("settings.checkUpdates.desc");
        D_Debug.Text = Loc.T("settings.debugLog.desc");
        T_LogFile.Text = Loc.T("settings.logFile");
        T_Copyright.Text = Loc.T("about.copyright");
        L_Website.Content = Loc.T("about.website");
        L_GitHub.Content = Loc.T("about.github");
        T_ApplyNote.Text = Loc.T("settings.applyNote");
        B_Close.Content = Loc.T("common.close");

        var v = typeof(SettingsWindow).Assembly.GetName().Version;
        AboutVersion.Text = Loc.Tf("settings.version", $"{v?.Major}.{v?.Minor}.{v?.Build}");

        // The combos hold localized labels of their own; the rows and the status pill too.
        RebuildAmbiguousCombo();
        RebuildLanguageCombo();
        RefreshStatus();
        RefreshExceptions();
    }

    /// <summary>
    /// The ambiguity choices are two language names (never translated) plus "Do not convert", which is.
    /// Rebuilt on a language change so that third entry follows the interface language.
    /// </summary>
    private void RebuildAmbiguousCombo()
    {
        bool wasLoading = _loading;
        _loading = true;
        var current = _s.AmbiguousLang;
        AmbiguousCombo.Items.Clear();
        foreach (var a in AmbLangs()) AmbiguousCombo.Items.Add(a);
        AmbiguousCombo.SelectedItem = AmbLangs().FirstOrDefault(a => a.Value == current) ?? AmbLangs()[0];
        _loading = wasLoading;
    }

    /// <summary>Rebuilt on a language change so "System default" and the "partial" tags follow it.</summary>
    private void RebuildLanguageCombo()
    {
        bool wasLoading = _loading;
        _loading = true;
        var langs = BuildLanguages();
        LanguageCombo.Items.Clear();
        foreach (var l in langs) LanguageCombo.Items.Add(l);
        LanguageCombo.SelectedItem = langs.FirstOrDefault(l => l.Code == _s.InterfaceLanguage) ?? langs[0];
        _loading = wasLoading;
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

    /// <summary>Re-read the exception lists — used when something outside this window changes them,
    /// such as accepting the "never convert this word" offer from a notification.</summary>
    internal void ReloadExceptions() => RefreshExceptions();

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
                ? Loc.T("settings.exceptions.emptyApps")
                : Loc.T("settings.exceptions.emptyWords");
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
            Title = Loc.T("settings.exceptions.picker.title"),
            Content = new StackPanel
            {
                Spacing = 10,
                Children =
                {
                    new TextBlock { Text = Loc.T("settings.exceptions.picker.note"), FontSize = 13, Opacity = 0.8 },
                    list,
                },
            },
            PrimaryButtonText = "Add",
            CloseButtonText = Loc.T("common.cancel"),
            DefaultButton = ContentDialogButton.Primary,
        };
        list.SelectionChanged += (_, _) =>
            dialog.PrimaryButtonText = list.SelectedItems.Count switch
            {
                0 => "Add",
                1 => Loc.T("settings.exceptions.picker.add1"),
                var n => Loc.Tf("settings.exceptions.picker.addN", n),
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

    // ---- drag-and-drop an .exe (or a shortcut to one) onto the list ------------------------------
    // The picker only lists *running* apps, so an app the user wants to exclude but isn't using right
    // now can only be added this way (or by browsing). Accepts .exe directly and resolves .lnk targets.

    private void ExcList_DragOver(object sender, DragEventArgs e)
    {
        if (SegIndex != 0 || !e.DataView.Contains(StandardDataFormats.StorageItems)) return;   // apps tab only
        e.AcceptedOperation = DataPackageOperation.Copy;
        e.DragUIOverride.Caption = Loc.T("settings.exceptions.dropHint");
        e.DragUIOverride.IsGlyphVisible = true;
        e.Handled = true;
    }

    private async void ExcList_Drop(object sender, DragEventArgs e)
    {
        if (SegIndex != 0 || !e.DataView.Contains(StandardDataFormats.StorageItems)) return;   // apps tab only
        e.Handled = true;
        try
        {
            var items = await e.DataView.GetStorageItemsAsync();
            int added = 0;
            foreach (var exe in items.OfType<Windows.Storage.StorageFile>().Select(f => ExeNameFrom(f.Path)))
            {
                if (exe is null) continue;
                if (SettingsManager.IsProtectedApp(exe)) continue;   // password managers stay locked
                if (_s.DeniedApps.Any(x => string.Equals(x, exe, StringComparison.OrdinalIgnoreCase))) continue;
                _s.DeniedApps.Add(exe);
                added++;
            }
            if (added == 0) return;
            Commit();
            RefreshExceptions();
        }
        catch (Exception ex)
        {
            Diagnostics.Log("exceptions drop failed: " + ex.Message);
        }
    }

    /// <summary>
    /// The exe file name to store for a dropped path: the file itself for an .exe, or a shortcut's
    /// target. Anything else (a document, a folder) returns null and is ignored.
    /// </summary>
    private static string? ExeNameFrom(string path)
    {
        if (path.EndsWith(".exe", StringComparison.OrdinalIgnoreCase))
            return System.IO.Path.GetFileName(path).ToLowerInvariant();

        if (path.EndsWith(".lnk", StringComparison.OrdinalIgnoreCase))
        {
            try
            {
                dynamic shell = Activator.CreateInstance(Type.GetTypeFromProgID("WScript.Shell")!)!;
                string target = shell.CreateShortcut(path).TargetPath;
                if (target.EndsWith(".exe", StringComparison.OrdinalIgnoreCase))
                    return System.IO.Path.GetFileName(target).ToLowerInvariant();
            }
            catch (Exception ex)
            {
                Diagnostics.Log($"could not resolve shortcut {path}: {ex.Message}");
            }
        }
        return null;
    }
}

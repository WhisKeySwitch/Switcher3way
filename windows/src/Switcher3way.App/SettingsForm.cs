using System.Drawing;
using System.Windows.Forms;

namespace Switcher3way.App;

/// <summary>
/// Preferences window, System-Settings style like the macOS app: tabbed (General / Auto-fix /
/// Advanced / About) with grouped controls and a unified, searchable exceptions manager
/// (Apps / Never-convert / Always-convert; password managers shown "always off", non-removable).
/// Edits working copies; applied to <see cref="SettingsManager"/> on Save.
/// </summary>
internal sealed class SettingsForm : Form
{
    private readonly SettingsManager _s;

    // General
    private readonly CheckBox _enabled = new() { Text = Loc.T("settings.autoSwitch"), AutoSize = true, Location = new Point(16, 26) };
    private readonly CheckBox _perApp = new() { Text = Loc.T("settings.perAppLayout"), AutoSize = true, Location = new Point(16, 52) };
    private readonly CheckBox _startup = new() { Text = Loc.T("settings.launchAtLogin"), AutoSize = true, Location = new Point(16, 78) };
    private readonly ComboBox _trigger = new() { DropDownStyle = ComboBoxStyle.DropDownList, Location = new Point(140, 24), Width = 170 };
    private readonly ComboBox _language = new() { DropDownStyle = ComboBoxStyle.DropDownList, Location = new Point(16, 132), Width = 300 };

    // Auto-fix
    private readonly CheckBox _autoFix = new() { Text = Loc.T("settings.autofix.title"), AutoSize = true, Location = new Point(16, 14) };
    private readonly ComboBox _filter = new() { DropDownStyle = ComboBoxStyle.DropDownList, Location = new Point(60, 22), Width = 140 };
    private readonly Label _count = new() { AutoSize = true, Location = new Point(206, 25), ForeColor = SystemColors.GrayText };
    private readonly TextBox _search = new() { Location = new Point(296, 22), Width = 104, PlaceholderText = Loc.T("settings.exceptions.search") };
    private readonly ListView _list = new() { Location = new Point(16, 50), Size = new Size(388, 200), View = View.Details, FullRowSelect = true, HeaderStyle = ColumnHeaderStyle.None };
    private readonly Button _remove = new() { Text = Loc.T("win.remove"), Location = new Point(16, 258), Size = new Size(160, 26) };
    private readonly TextBox _addBox = new() { Location = new Point(16, 292), Width = 300, PlaceholderText = Loc.T("win.addEntry") };
    private readonly Button _add = new() { Text = Loc.T("common.add"), Location = new Point(322, 290), Size = new Size(60, 26) };

    // Advanced
    private readonly CheckBox _debug = new() { Text = Loc.T("settings.debugLog"), AutoSize = true, Location = new Point(16, 20) };

    // Working copies (applied on Save).
    private readonly List<string> _apps, _never, _always;

    private const string RepoUrl = "https://github.com/WhisKeySwitch/Switcher3way";
    private const string SiteUrl = "https://whiskeyswitch.github.io/Switcher3way/";

    private sealed record KeyItem(string Name, int Vk, bool Double = false) { public override string ToString() => Name; }
    private static readonly KeyItem[] TriggerKeys =
    {
        new("F8", 0x77), new("F9", 0x78), new("F10", 0x79), new("F11", 0x7A), new("F12", 0x7B),
        new("Pause/Break", 0x13), new("Scroll Lock", 0x91), new("Right Ctrl", 0xA3),
        new("Double Shift", 0x10, true), new("Double Ctrl", 0x11, true), new("Double Alt", 0x12, true),
    };

    // Interface-language override; empty code = follow the system UI culture. Names are native.
    private sealed record LangItem(string Code, string Name) { public override string ToString() => Name; }
    private static readonly LangItem[] Languages =
    {
        new("en", "English"), new("uk", "Українська"), new("ru", "Русский"), new("be", "Беларуская"),
        new("de", "Deutsch"), new("fr", "Français"), new("es", "Español"), new("pt", "Português"),
        new("pl", "Polski"), new("zh", "中文"), new("ja", "日本語"), new("ko", "한국어"),
        new("el", "Ελληνικά"), new("bg", "Български"), new("hy", "Հայերեն"), new("ka", "ქართული"),
    };

    public SettingsForm(SettingsManager s)
    {
        _s = s;
        _apps = new List<string>(s.DeniedApps);
        _never = new List<string>(s.NeverConvertWords);
        _always = new List<string>(s.AlwaysConvertWords);

        Text = "Switcher3way — Settings";
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = MinimizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        Font = new Font("Segoe UI", 9f);
        ClientSize = new Size(468, 470);
        try { Icon = Icon.ExtractAssociatedIcon(Environment.ProcessPath!); } catch { /* dev host */ }

        var tabs = new TabControl { Location = new Point(8, 8), Size = new Size(452, 410) };
        tabs.TabPages.Add(BuildGeneral());
        tabs.TabPages.Add(BuildAutoFix());
        tabs.TabPages.Add(BuildAdvanced());
        tabs.TabPages.Add(BuildAbout());
        Controls.Add(tabs);

        var save = new Button { Text = Loc.T("win.save"), Size = new Size(80, 26), Location = new Point(292, 428), DialogResult = DialogResult.OK };
        var cancel = new Button { Text = Loc.T("common.cancel"), Size = new Size(80, 26), Location = new Point(378, 428), DialogResult = DialogResult.Cancel };
        save.Click += (_, _) => Apply();
        AcceptButton = save;
        CancelButton = cancel;
        Controls.Add(save);
        Controls.Add(cancel);

        Populate();
    }

    private TabPage BuildGeneral()
    {
        var p = new TabPage(Loc.T("settings.tab.general"));
        var behavior = new GroupBox { Text = Loc.T("settings.group.system"), Location = new Point(12, 12), Size = new Size(420, 168) };
        behavior.Controls.Add(new Label { Text = Loc.T("settings.language"), AutoSize = true, Location = new Point(16, 110) });
        behavior.Controls.AddRange(new Control[] { _enabled, _perApp, _startup, _language });
        var trig = new GroupBox { Text = Loc.T("settings.group.trigger"), Location = new Point(12, 190), Size = new Size(420, 64) };
        trig.Controls.Add(new Label { Text = Loc.T("settings.trigger"), AutoSize = true, Location = new Point(16, 28) });
        _trigger.Items.AddRange(TriggerKeys);
        trig.Controls.Add(_trigger);
        p.Controls.AddRange(new Control[] { behavior, trig });
        return p;
    }

    private TabPage BuildAutoFix()
    {
        var p = new TabPage(Loc.T("settings.tab.autofix"));
        p.Controls.Add(_autoFix);
        var box = new GroupBox { Text = Loc.T("settings.group.exceptions"), Location = new Point(12, 42), Size = new Size(420, 328) };
        box.Controls.Add(new Label { Text = Loc.T("win.show"), AutoSize = true, Location = new Point(16, 25) });
        _filter.Items.AddRange(new object[] { Loc.T("settings.exceptions.seg.apps"), Loc.T("settings.exceptions.seg.never"), Loc.T("settings.exceptions.seg.always") });
        _filter.SelectedIndexChanged += (_, _) => RefreshList();
        _search.TextChanged += (_, _) => RefreshList();
        _list.Columns.Add("", 360);
        _list.SelectedIndexChanged += (_, _) => UpdateRemoveEnabled();
        _add.Click += (_, _) => AddEntry();
        _remove.Click += (_, _) => RemoveEntry();
        _addBox.KeyDown += (_, e) => { if (e.KeyCode == Keys.Enter) { AddEntry(); e.SuppressKeyPress = true; } };
        box.Controls.AddRange(new Control[] { _filter, _count, _search, _list, _addBox, _add, _remove });
        p.Controls.Add(box);
        return p;
    }

    private TabPage BuildAdvanced()
    {
        var p = new TabPage(Loc.T("settings.tab.advanced"));
        p.Controls.Add(_debug);
        var open = new Button { Text = Loc.T("win.openLog"), Location = new Point(16, 48), Size = new Size(160, 26) };
        open.Click += (_, _) => Open(Diagnostics.Dir);
        p.Controls.Add(open);
        p.Controls.Add(new Label { Text = "The debug log is written only while enabled, at:\n" + Diagnostics.FilePath, AutoSize = true, Location = new Point(16, 84), ForeColor = SystemColors.GrayText });
        return p;
    }

    private TabPage BuildAbout()
    {
        var p = new TabPage(Loc.T("settings.tab.about"));
        var v = typeof(SettingsForm).Assembly.GetName().Version;
        p.Controls.Add(new Label { Text = "Switcher3way", Font = new Font("Segoe UI", 14f, FontStyle.Bold), AutoSize = true, Location = new Point(16, 16) });
        p.Controls.Add(new Label { Text = Loc.T("win.tagline"), AutoSize = true, MaximumSize = new Size(410, 0), Location = new Point(16, 50) });
        p.Controls.Add(new Label { Text = $"Version {v?.Major}.{v?.Minor} — Windows preview", AutoSize = true, Location = new Point(16, 76), ForeColor = SystemColors.GrayText });
        p.Controls.Add(new Label { Text = "MIT License · a fork of RuSwitcher, generalized to N-way.", AutoSize = true, Location = new Point(16, 100), ForeColor = SystemColors.GrayText });
        p.Controls.Add(Link("Website", SiteUrl, 132));
        p.Controls.Add(Link("GitHub", RepoUrl, 156));
        return p;
    }

    private static LinkLabel Link(string text, string url, int y)
    {
        var l = new LinkLabel { Text = text, AutoSize = true, Location = new Point(16, y) };
        l.LinkClicked += (_, _) => Open(url);
        return l;
    }

    private static void Open(string target)
    {
        try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(target) { UseShellExecute = true }); }
        catch { /* best-effort */ }
    }

    // ---- exceptions list -------------------------------------------------------------------
    // Keyed by index (0=Apps, 1=Never, 2=Always) so localized item text doesn't affect logic.
    private int FilterIndex => _filter.SelectedIndex < 0 ? 0 : _filter.SelectedIndex;
    private bool AppsFilter => FilterIndex == 0;
    private List<string> CurrentList => FilterIndex == 1 ? _never : FilterIndex == 2 ? _always : _apps;

    private void RefreshList()
    {
        _list.BeginUpdate();
        _list.Items.Clear();
        string q = _search.Text.Trim();
        bool Match(string x) => q.Length == 0 || x.Contains(q, StringComparison.OrdinalIgnoreCase);

        int total = 0;
        if (AppsFilter)
        {
            foreach (var pApp in SettingsManager.ProtectedApps)
            {
                total++;
                if (Match(pApp))
                    _list.Items.Add(new ListViewItem($"{pApp}    ({Loc.T("settings.exceptions.alwaysOff")})") { ForeColor = SystemColors.GrayText, Tag = "protected" });
            }
        }
        foreach (var e in CurrentList)
        {
            total++;
            if (Match(e)) _list.Items.Add(new ListViewItem(e) { Tag = "user" });
        }
        _list.Columns[0].Width = -2; // fill the list width; no horizontal scrollbar
        _list.EndUpdate();
        _count.Text = $"({total})";
        UpdateRemoveEnabled();
    }

    private void UpdateRemoveEnabled() =>
        _remove.Enabled = _list.SelectedItems.Count > 0 && (string?)_list.SelectedItems[0].Tag != "protected";

    private void AddEntry()
    {
        var v = _addBox.Text.Trim();
        if (v.Length == 0) return;
        if (AppsFilter) v = v.ToLowerInvariant();
        if (!CurrentList.Any(x => string.Equals(x, v, StringComparison.OrdinalIgnoreCase)))
            CurrentList.Add(v);
        _addBox.Clear();
        RefreshList();
    }

    private void RemoveEntry()
    {
        if (_list.SelectedItems.Count == 0) return;
        var item = _list.SelectedItems[0];
        if ((string?)item.Tag == "protected") return;
        CurrentList.RemoveAll(x => string.Equals(x, item.Text, StringComparison.OrdinalIgnoreCase));
        RefreshList();
    }

    // ---- load / save -----------------------------------------------------------------------
    private void Populate()
    {
        _enabled.Checked = _s.Enabled;
        _autoFix.Checked = _s.AutoFix;
        _perApp.Checked = _s.PerAppMemory;
        _debug.Checked = _s.DebugLog;
        _startup.Checked = StartupShortcut.IsEnabled;
        _trigger.SelectedItem = TriggerKeys.FirstOrDefault(k => k.Vk == _s.TriggerKey && k.Double == _s.TriggerDoubleTap) ?? TriggerKeys[1];
        if (_language.Items.Count == 0)
        {
            _language.Items.Add(new LangItem("", Loc.T("settings.languageAuto")));
            _language.Items.AddRange(Languages);
        }
        _language.SelectedItem = _language.Items.Cast<LangItem>().FirstOrDefault(l => l.Code == _s.InterfaceLanguage) ?? _language.Items[0];
        _filter.SelectedIndex = 0;
        RefreshList();
    }

    private void Apply()
    {
        _s.Enabled = _enabled.Checked;
        _s.AutoFix = _autoFix.Checked;
        _s.PerAppMemory = _perApp.Checked;
        _s.DebugLog = _debug.Checked;
        if (_trigger.SelectedItem is KeyItem k) { _s.TriggerKey = k.Vk; _s.TriggerDoubleTap = k.Double; }
        if (_language.SelectedItem is LangItem lang) { _s.InterfaceLanguage = lang.Code; Loc.Configure(lang.Code); }
        _s.DeniedApps = _apps;
        _s.NeverConvertWords = _never;
        _s.AlwaysConvertWords = _always;
        _s.Save();
        if (_startup.Checked != StartupShortcut.IsEnabled) StartupShortcut.Set(_startup.Checked);
    }
}

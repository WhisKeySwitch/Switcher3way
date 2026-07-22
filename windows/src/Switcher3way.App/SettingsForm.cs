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
    private readonly CheckBox _enabled = new() { Text = "Enabled", AutoSize = true, Location = new Point(16, 26) };
    private readonly CheckBox _perApp = new() { Text = "Remember layout per app", AutoSize = true, Location = new Point(16, 52) };
    private readonly CheckBox _startup = new() { Text = "Start at login", AutoSize = true, Location = new Point(16, 78) };
    private readonly ComboBox _trigger = new() { DropDownStyle = ComboBoxStyle.DropDownList, Location = new Point(110, 24), Width = 160 };

    // Auto-fix
    private readonly CheckBox _autoFix = new() { Text = "Auto-fix wrong-layout words as you type", AutoSize = true, Location = new Point(16, 14) };
    private readonly ComboBox _filter = new() { DropDownStyle = ComboBoxStyle.DropDownList, Location = new Point(60, 22), Width = 140 };
    private readonly Label _count = new() { AutoSize = true, Location = new Point(206, 25), ForeColor = SystemColors.GrayText };
    private readonly TextBox _search = new() { Location = new Point(296, 22), Width = 104, PlaceholderText = "Search" };
    private readonly ListView _list = new() { Location = new Point(16, 50), Size = new Size(388, 200), View = View.Details, FullRowSelect = true, HeaderStyle = ColumnHeaderStyle.None };
    private readonly Button _remove = new() { Text = "Remove selected", Location = new Point(16, 258), Size = new Size(140, 26) };
    private readonly TextBox _addBox = new() { Location = new Point(16, 292), Width = 300, PlaceholderText = "Add entry, then click Add" };
    private readonly Button _add = new() { Text = "Add", Location = new Point(322, 290), Size = new Size(60, 26) };

    // Advanced
    private readonly CheckBox _debug = new() { Text = "Debug log", AutoSize = true, Location = new Point(16, 20) };

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

        var save = new Button { Text = "Save", Size = new Size(80, 26), Location = new Point(292, 428), DialogResult = DialogResult.OK };
        var cancel = new Button { Text = "Cancel", Size = new Size(80, 26), Location = new Point(378, 428), DialogResult = DialogResult.Cancel };
        save.Click += (_, _) => Apply();
        AcceptButton = save;
        CancelButton = cancel;
        Controls.Add(save);
        Controls.Add(cancel);

        Populate();
    }

    private TabPage BuildGeneral()
    {
        var p = new TabPage("General");
        var behavior = new GroupBox { Text = "Behavior", Location = new Point(12, 12), Size = new Size(420, 116) };
        behavior.Controls.AddRange(new Control[] { _enabled, _perApp, _startup });
        var trig = new GroupBox { Text = "Manual trigger", Location = new Point(12, 138), Size = new Size(420, 64) };
        trig.Controls.Add(new Label { Text = "Trigger key:", AutoSize = true, Location = new Point(16, 28) });
        _trigger.Items.AddRange(TriggerKeys);
        trig.Controls.Add(_trigger);
        p.Controls.AddRange(new Control[] { behavior, trig });
        return p;
    }

    private TabPage BuildAutoFix()
    {
        var p = new TabPage("Auto-fix");
        p.Controls.Add(_autoFix);
        var box = new GroupBox { Text = "Exceptions", Location = new Point(12, 42), Size = new Size(420, 328) };
        box.Controls.Add(new Label { Text = "Show:", AutoSize = true, Location = new Point(16, 25) });
        _filter.Items.AddRange(new object[] { "Apps", "Never convert", "Always convert" });
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
        var p = new TabPage("Advanced");
        p.Controls.Add(_debug);
        var open = new Button { Text = "Open log folder", Location = new Point(16, 48), Size = new Size(130, 26) };
        open.Click += (_, _) => Open(Diagnostics.Dir);
        p.Controls.Add(open);
        p.Controls.Add(new Label { Text = "The debug log is written only while enabled, at:\n" + Diagnostics.FilePath, AutoSize = true, Location = new Point(16, 84), ForeColor = SystemColors.GrayText });
        return p;
    }

    private TabPage BuildAbout()
    {
        var p = new TabPage("About");
        var v = typeof(SettingsForm).Assembly.GetName().Version;
        p.Controls.Add(new Label { Text = "Switcher3way", Font = new Font("Segoe UI", 14f, FontStyle.Bold), AutoSize = true, Location = new Point(16, 16) });
        p.Controls.Add(new Label { Text = "Auto-fix your keyboard layout across English, Ukrainian, and Russian.", AutoSize = true, Location = new Point(16, 50) });
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
    private string Filter => _filter.SelectedItem as string ?? "Apps";
    private List<string> CurrentList => Filter == "Never convert" ? _never : Filter == "Always convert" ? _always : _apps;

    private void RefreshList()
    {
        _list.BeginUpdate();
        _list.Items.Clear();
        string q = _search.Text.Trim();
        bool Match(string x) => q.Length == 0 || x.Contains(q, StringComparison.OrdinalIgnoreCase);

        int total = 0;
        if (Filter == "Apps")
        {
            foreach (var pApp in SettingsManager.ProtectedApps)
            {
                total++;
                if (Match(pApp))
                    _list.Items.Add(new ListViewItem($"{pApp}    (always off)") { ForeColor = SystemColors.GrayText, Tag = "protected" });
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
        if (Filter == "Apps") v = v.ToLowerInvariant();
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
        _s.DeniedApps = _apps;
        _s.NeverConvertWords = _never;
        _s.AlwaysConvertWords = _always;
        _s.Save();
        if (_startup.Checked != StartupShortcut.IsEnabled) StartupShortcut.Set(_startup.Checked);
    }
}

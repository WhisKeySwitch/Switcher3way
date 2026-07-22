using System.Drawing;
using System.Windows.Forms;

namespace Switcher3way.App;

/// <summary>
/// Preferences window: the feature toggles plus editable exception lists (denied apps,
/// never-convert / always-convert words). One entry per line. Changes take effect on Save
/// (the Engine reads settings live).
/// </summary>
internal sealed class SettingsForm : Form
{
    private readonly SettingsManager _s;
    private readonly CheckBox _enabled, _autoFix, _perApp, _debug;
    private readonly TextBox _denied, _never, _always;

    public SettingsForm(SettingsManager s)
    {
        _s = s;
        Text = "Switcher3way — Settings";
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = MinimizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        Font = new Font("Segoe UI", 9f);
        ClientSize = new Size(440, 524);

        const int x = 14, w = 412;
        int y = 12;
        _enabled = Check("Enabled", ref y, x);
        _autoFix = Check("Auto-fix as you type", ref y, x);
        _perApp = Check("Remember layout per app", ref y, x);
        _debug = Check("Debug log", ref y, x);

        y += 6;
        _denied = ListField("Denied apps (one exe name per line, e.g. keepass.exe)", ref y, x, w);
        _never = ListField("Never convert (one word per line)", ref y, x, w);
        _always = ListField("Always convert (one word per line)", ref y, x, w);

        var save = new Button { Text = "Save", Size = new Size(80, 26), Location = new Point(x + w - 168, y + 6), DialogResult = DialogResult.OK };
        var cancel = new Button { Text = "Cancel", Size = new Size(80, 26), Location = new Point(x + w - 82, y + 6), DialogResult = DialogResult.Cancel };
        save.Click += (_, _) => Apply();
        AcceptButton = save;
        CancelButton = cancel;
        Controls.Add(save);
        Controls.Add(cancel);

        Populate();
    }

    private CheckBox Check(string text, ref int y, int x)
    {
        var c = new CheckBox { Text = text, Location = new Point(x, y), AutoSize = true };
        Controls.Add(c);
        y += 26;
        return c;
    }

    private TextBox ListField(string label, ref int y, int x, int w)
    {
        Controls.Add(new Label { Text = label, Location = new Point(x, y), AutoSize = true });
        y += 20;
        var t = new TextBox { Location = new Point(x, y), Size = new Size(w, 90), Multiline = true, ScrollBars = ScrollBars.Vertical, WordWrap = false };
        Controls.Add(t);
        y += 98;
        return t;
    }

    private void Populate()
    {
        _enabled.Checked = _s.Enabled;
        _autoFix.Checked = _s.AutoFix;
        _perApp.Checked = _s.PerAppMemory;
        _debug.Checked = _s.DebugLog;
        _denied.Text = string.Join(Environment.NewLine, _s.DeniedApps);
        _never.Text = string.Join(Environment.NewLine, _s.NeverConvertWords);
        _always.Text = string.Join(Environment.NewLine, _s.AlwaysConvertWords);
    }

    private void Apply()
    {
        _s.Enabled = _enabled.Checked;
        _s.AutoFix = _autoFix.Checked;
        _s.PerAppMemory = _perApp.Checked;
        _s.DebugLog = _debug.Checked;
        _s.DeniedApps = Lines(_denied);
        _s.NeverConvertWords = Lines(_never);
        _s.AlwaysConvertWords = Lines(_always);
        _s.Save();
    }

    private static List<string> Lines(TextBox t) =>
        t.Lines.Select(l => l.Trim()).Where(l => l.Length > 0).Distinct().ToList();
}

using System.Drawing;
using System.Windows.Forms;

namespace Switcher3way.App;

/// <summary>
/// System-tray presence: status icon + menu (enable / auto-fix / pause / quit), mirroring the
/// macOS menu-bar item. Owns the <see cref="Engine"/> and <see cref="SettingsManager"/>.
/// </summary>
internal sealed class TrayApp : IDisposable
{
    private readonly SettingsManager _settings;
    private readonly Engine _engine;
    private readonly NotifyIcon _icon;
    private readonly Icon _activeIcon, _pausedIcon;

    private readonly ToolStripMenuItem _enabledItem, _autoFixItem;
    private readonly System.Windows.Forms.Timer _refresh;

    public TrayApp()
    {
        _settings = SettingsManager.Load();
        _engine = new Engine(_settings);

        _activeIcon = MakeIcon("S", Color.FromArgb(59, 91, 219));   // blue = active
        _pausedIcon = MakeIcon("S", Color.FromArgb(120, 124, 133)); // grey = off/paused

        _enabledItem = new ToolStripMenuItem("Enabled", null, (_, _) => Toggle(() => _settings.Enabled = !_settings.Enabled));
        _autoFixItem = new ToolStripMenuItem("Auto-fix as you type", null, (_, _) => Toggle(() => _settings.AutoFix = !_settings.AutoFix));

        var pause = new ToolStripMenuItem("Pause");
        pause.DropDownItems.Add(new ToolStripMenuItem("30 minutes", null, (_, _) => DoPause(TimeSpan.FromMinutes(30))));
        pause.DropDownItems.Add(new ToolStripMenuItem("1 hour", null, (_, _) => DoPause(TimeSpan.FromHours(1))));
        pause.DropDownItems.Add(new ToolStripMenuItem("Until restart", null, (_, _) => DoPause(null)));
        pause.DropDownItems.Add(new ToolStripSeparator());
        pause.DropDownItems.Add(new ToolStripMenuItem("Resume", null, (_, _) => { _settings.Resume(); UpdateUi(); }));

        var menu = new ContextMenuStrip();
        var header = new ToolStripMenuItem("Switcher3way") { Enabled = false };
        menu.Items.Add(header);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(_enabledItem);
        menu.Items.Add(_autoFixItem);
        menu.Items.Add(pause);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem("Quit", null, (_, _) => Quit()));

        _icon = new NotifyIcon { Icon = _activeIcon, Text = "Switcher3way", Visible = true, ContextMenuStrip = menu };

        _engine.Start();
        UpdateUi();

        // Refresh so a timed pause visibly resumes without a click.
        _refresh = new System.Windows.Forms.Timer { Interval = 30_000 };
        _refresh.Tick += (_, _) => UpdateUi();
        _refresh.Start();
    }

    private void Toggle(Action mutate) { mutate(); _settings.Save(); UpdateUi(); }
    private void DoPause(TimeSpan? d) { _settings.Pause(d); UpdateUi(); }

    private void UpdateUi()
    {
        _enabledItem.Checked = _settings.Enabled;
        _autoFixItem.Checked = _settings.AutoFix;
        bool on = _settings.EffectivelyEnabled;
        _icon.Icon = on ? _activeIcon : _pausedIcon;
        _icon.Text = on ? "Switcher3way — on"
                        : _settings.IsPaused ? "Switcher3way — paused" : "Switcher3way — off";
    }

    private void Quit()
    {
        _icon.Visible = false;
        _engine.Stop();
        Application.Exit();
    }

    /// <summary>A simple round tray glyph (a letter on a colored disc) so we don't depend on assets.</summary>
    private static Icon MakeIcon(string glyph, Color bg)
    {
        using var bmp = new Bitmap(32, 32);
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            g.Clear(Color.Transparent);
            using var brush = new SolidBrush(bg);
            g.FillEllipse(brush, 1, 1, 30, 30);
            using var font = new Font("Segoe UI", 18, FontStyle.Bold, GraphicsUnit.Pixel);
            using var fg = new SolidBrush(Color.White);
            var sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center };
            g.DrawString(glyph, font, fg, new RectangleF(0, 0, 32, 32), sf);
        }
        IntPtr h = bmp.GetHicon();
        var icon = (Icon)Icon.FromHandle(h).Clone(); // clone so we can free the HICON immediately
        Native.DestroyIcon(h);
        return icon;
    }

    public void Dispose()
    {
        _refresh.Dispose();
        _icon.Dispose();
        _activeIcon.Dispose();
        _pausedIcon.Dispose();
    }
}

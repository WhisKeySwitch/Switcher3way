using System.Drawing;
using System.Globalization;
using System.Windows.Forms;

namespace Switcher3way.App;

/// <summary>
/// System-tray presence: a status icon that live-tracks the current keyboard layout as a small
/// flag (Ukraine blue/yellow, Russia tricolor, an "EN" badge for English), plus the menu
/// (enable / auto-fix / per-app / pause / debug log / quit). Mirrors the macOS menu-bar item.
/// Owns the <see cref="Engine"/> and <see cref="SettingsManager"/>.
/// </summary>
internal sealed class TrayApp : IDisposable
{
    private readonly SettingsManager _settings;
    private readonly Engine _engine;
    private readonly NotifyIcon _icon;
    private readonly Dictionary<string, Icon> _flags = new(); // cache: "<lang>:<dim>" -> icon
    private string _iconKey = "";

    private readonly ToolStripMenuItem _enabledItem, _autoFixItem, _perAppItem, _debugItem;
    private readonly System.Windows.Forms.Timer _poll;
    private readonly System.Threading.SynchronizationContext? _ui;

    public TrayApp()
    {
        _ui = System.Threading.SynchronizationContext.Current; // WinForms UI context (ctor runs on the UI thread)
        _settings = SettingsManager.Load();
        _engine = new Engine(_settings);
        _engine.Notify += ShowBalloon;

        _enabledItem = new ToolStripMenuItem("Enabled", null, (_, _) => Toggle(() => _settings.Enabled = !_settings.Enabled));
        _autoFixItem = new ToolStripMenuItem("Auto-fix as you type", null, (_, _) => Toggle(() => _settings.AutoFix = !_settings.AutoFix));
        _perAppItem = new ToolStripMenuItem("Remember layout per app", null, (_, _) => Toggle(() => _settings.PerAppMemory = !_settings.PerAppMemory));
        _debugItem = new ToolStripMenuItem("Debug log", null, (_, _) => Toggle(() => _settings.DebugLog = !_settings.DebugLog));

        var pause = new ToolStripMenuItem("Pause");
        pause.DropDownItems.Add(new ToolStripMenuItem("30 minutes", null, (_, _) => DoPause(TimeSpan.FromMinutes(30))));
        pause.DropDownItems.Add(new ToolStripMenuItem("1 hour", null, (_, _) => DoPause(TimeSpan.FromHours(1))));
        pause.DropDownItems.Add(new ToolStripMenuItem("Until restart", null, (_, _) => DoPause(null)));
        pause.DropDownItems.Add(new ToolStripSeparator());
        pause.DropDownItems.Add(new ToolStripMenuItem("Resume", null, (_, _) => { _settings.Resume(); UpdateUi(); }));

        var menu = new ContextMenuStrip();
        menu.Items.Add(new ToolStripMenuItem("Switcher3way") { Enabled = false });
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(_enabledItem);
        menu.Items.Add(_autoFixItem);
        menu.Items.Add(_perAppItem);
        menu.Items.Add(pause);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(_debugItem);
        menu.Items.Add(new ToolStripMenuItem("Open log folder", null, (_, _) => OpenLogFolder()));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem("Quit", null, (_, _) => Quit()));

        _icon = new NotifyIcon { Text = "Switcher3way", ContextMenuStrip = menu };
        RefreshIcon();          // sets the initial flag icon
        _icon.Visible = true;

        _engine.Start();
        UpdateUi();

        // Poll the foreground layout so the flag follows it live (also picks up pause expiry).
        _poll = new System.Windows.Forms.Timer { Interval = 400 };
        _poll.Tick += (_, _) => RefreshIcon();
        _poll.Start();
    }

    private void Toggle(Action mutate) { mutate(); _settings.Save(); UpdateUi(); }
    private void DoPause(TimeSpan? d) { _settings.Pause(d); UpdateUi(); }

    private void UpdateUi()
    {
        _enabledItem.Checked = _settings.Enabled;
        _autoFixItem.Checked = _settings.AutoFix;
        _perAppItem.Checked = _settings.PerAppMemory;
        _debugItem.Checked = _settings.DebugLog;
        RefreshIcon();
    }

    /// <summary>Set the tray icon to the current layout's flag (dimmed + paused-marked when off).</summary>
    private void RefreshIcon()
    {
        string lang = CurrentLang();
        bool dim = !_settings.EffectivelyEnabled;
        string key = $"{lang}:{dim}";
        if (key != _iconKey) { _icon.Icon = FlagIcon(lang, dim); _iconKey = key; }
        _icon.Text = dim
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

    private Icon FlagIcon(string lang, bool dim)
    {
        var key = $"{lang}:{dim}";
        if (!_flags.TryGetValue(key, out var ic)) { ic = MakeFlag(lang, dim); _flags[key] = ic; }
        return ic;
    }

    private void ShowBalloon(string message)
    {
        // Engine fires this from a worker thread → marshal to the UI thread for the NotifyIcon.
        void Show() => _icon.ShowBalloonTip(4000, "Switcher3way", message, ToolTipIcon.Info);
        if (_ui is not null) _ui.Post(_ => Show(), null); else Show();
    }

    private static void OpenLogFolder()
    {
        try
        {
            Directory.CreateDirectory(Diagnostics.Dir);
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(Diagnostics.Dir) { UseShellExecute = true });
        }
        catch { /* best-effort */ }
    }

    private void Quit()
    {
        _icon.Visible = false;
        _engine.Stop();
        Application.Exit();
    }

    // ---- Flag drawing ----------------------------------------------------------------------
    private static Icon MakeFlag(string lang, bool dim)
    {
        using var bmp = new Bitmap(32, 32);
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            g.Clear(Color.Transparent);
            var r = new Rectangle(2, 6, 28, 20);

            switch (lang)
            {
                case "ru":
                    Bands(g, r, Color.White, Color.FromArgb(0x00, 0x39, 0xA6), Color.FromArgb(0xD5, 0x2B, 0x1E));
                    break;
                case "uk":
                    Bands(g, r, Color.FromArgb(0x00, 0x57, 0xB7), Color.FromArgb(0xFF, 0xD5, 0x00));
                    break;
                default: // en or unknown: a coloured badge with the 2-letter code
                    using (var b = new SolidBrush(Color.FromArgb(0x2B, 0x36, 0x52))) g.FillRectangle(b, r);
                    var code = (lang.Length >= 2 ? lang[..2] : lang).ToUpperInvariant();
                    using (var f = new Font("Segoe UI", 12, FontStyle.Bold, GraphicsUnit.Pixel))
                    using (var fb = new SolidBrush(Color.White))
                    {
                        var sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center };
                        g.DrawString(code, f, fb, new RectangleF(r.X, r.Y, r.Width, r.Height), sf);
                    }
                    break;
            }

            using (var pen = new Pen(Color.FromArgb(90, 0, 0, 0))) g.DrawRectangle(pen, r);

            if (dim)
            {
                using var ov = new SolidBrush(Color.FromArgb(150, 110, 110, 110));
                g.FillRectangle(ov, 0, 0, 32, 32);
                using var pb = new SolidBrush(Color.FromArgb(235, 40, 40, 40)); // pause bars
                g.FillRectangle(pb, 11, 10, 3, 12);
                g.FillRectangle(pb, 18, 10, 3, 12);
            }
        }
        IntPtr h = bmp.GetHicon();
        var icon = (Icon)Icon.FromHandle(h).Clone();
        Native.DestroyIcon(h);
        return icon;
    }

    private static void Bands(Graphics g, Rectangle r, params Color[] colors)
    {
        int band = r.Height / colors.Length;
        for (int i = 0; i < colors.Length; i++)
        {
            int y = r.Y + i * band;
            int h = (i == colors.Length - 1) ? r.Bottom - y : band; // last band fills remainder
            using var b = new SolidBrush(colors[i]);
            g.FillRectangle(b, r.X, y, r.Width, h);
        }
    }

    public void Dispose()
    {
        _poll.Dispose();
        _icon.Dispose();
        foreach (var ic in _flags.Values) ic.Dispose();
    }
}

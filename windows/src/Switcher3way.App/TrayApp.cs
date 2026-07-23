using System.Drawing;
using System.Globalization;
using System.IO;
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

    private readonly ToolStripMenuItem _enabledItem, _autoFixItem, _perAppItem, _debugItem, _updateItem;
    private HelpWindow? _help; // built-in help window (single instance)
    private readonly UpdateChecker _updater;
    private readonly System.Windows.Forms.Timer _poll;
    private readonly System.Threading.SynchronizationContext? _ui;

    public TrayApp()
    {
        _ui = System.Threading.SynchronizationContext.Current; // WinForms UI context (ctor runs on the UI thread)
        _settings = SettingsManager.Load();
        Loc.Configure(_settings.InterfaceLanguage); // apply any forced UI language before building the menu
        _engine = new Engine(_settings);
        _engine.Notify += ShowBalloon;

        _enabledItem = new ToolStripMenuItem(Loc.T("menu.autoSwitch"), null, (_, _) => Toggle(() => _settings.Enabled = !_settings.Enabled));
        _autoFixItem = new ToolStripMenuItem(Loc.T("menu.autofix"), null, (_, _) => Toggle(() => _settings.AutoFix = !_settings.AutoFix));
        _perAppItem = new ToolStripMenuItem(Loc.T("settings.perAppLayout"), null, (_, _) => Toggle(() => _settings.PerAppMemory = !_settings.PerAppMemory));
        _debugItem = new ToolStripMenuItem(Loc.T("settings.debugLog"), null, (_, _) => Toggle(() => _settings.DebugLog = !_settings.DebugLog));

        _updater = new UpdateChecker(_settings, _ui ?? new System.Threading.SynchronizationContext(), Quit);
        _updater.StateChanged += () => RefreshUpdateItem();
        _updateItem = new ToolStripMenuItem(Loc.T("menu.checkUpdates"), null, (_, _) => _updater.CheckManually());

        var pause = new ToolStripMenuItem(Loc.T("menu.pause"));
        pause.DropDownItems.Add(new ToolStripMenuItem(Loc.T("menu.pause.30m"), null, (_, _) => DoPause(TimeSpan.FromMinutes(30))));
        pause.DropDownItems.Add(new ToolStripMenuItem(Loc.T("menu.pause.1h"), null, (_, _) => DoPause(TimeSpan.FromHours(1))));
        pause.DropDownItems.Add(new ToolStripMenuItem(Loc.T("menu.pause.untilRestart"), null, (_, _) => DoPause(null)));
        pause.DropDownItems.Add(new ToolStripSeparator());
        pause.DropDownItems.Add(new ToolStripMenuItem(Loc.T("menu.resume"), null, (_, _) => { _settings.Resume(); UpdateUi(); }));

        var menu = new ContextMenuStrip();
        menu.Items.Add(new ToolStripMenuItem("Switcher3way") { Enabled = false });
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(_enabledItem);
        menu.Items.Add(_autoFixItem);
        menu.Items.Add(_perAppItem);
        menu.Items.Add(pause);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem(Loc.T("menu.settings"), null, (_, _) => OpenSettings()));
        menu.Items.Add(_debugItem);
        menu.Items.Add(new ToolStripMenuItem(Loc.T("win.openLog"), null, (_, _) => OpenLogFolder()));
        menu.Items.Add(new ToolStripMenuItem(Loc.T("menu.help"), null, (_, _) => OpenHelp()));
        menu.Items.Add(_updateItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem(Loc.T("menu.quit"), null, (_, _) => Quit()));

        _icon = new NotifyIcon { Text = "Switcher3way", ContextMenuStrip = menu };
        RefreshIcon();          // sets the initial flag icon
        _icon.Visible = true;

        _engine.Start();
        UpdateUi();
        _updater.StartSchedule();

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

    /// <summary>Relabel/disable the update menu item while a check or install is running.</summary>
    private void RefreshUpdateItem()
    {
        _updateItem.Text = _updater.IsBusy ? Loc.T("menu.checkingUpdates") : Loc.T("menu.checkUpdates");
        _updateItem.Enabled = !_updater.IsBusy;
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

    private void OpenSettings()
    {
        using var form = new SettingsForm(_settings);
        if (form.ShowDialog() == DialogResult.OK) { UpdateUi(); _updater.StartSchedule(); }
    }

    /// <summary>Open the built-in Help window (single instance) in the current UI language.</summary>
    private void OpenHelp()
    {
        if (_help is null || _help.IsDisposed)
        {
            _help = new HelpWindow(Loc.Language);
            _help.FormClosed += (_, _) => _help = null;
        }
        _help.Show();
        _help.WindowState = FormWindowState.Normal;
        _help.Activate();
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
            g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
            g.PixelOffsetMode = System.Drawing.Drawing2D.PixelOffsetMode.HighQuality;
            g.Clear(Color.Transparent);
            var r = new Rectangle(2, 6, 28, 20);

            var img = FlagImage(lang);
            if (img is not null)
            {
                g.DrawImage(img, r);
            }
            else // unknown language: a coloured badge with the 2-letter code
            {
                using var b = new SolidBrush(Color.FromArgb(0x2B, 0x36, 0x52));
                g.FillRectangle(b, r);
                var code = (lang.Length >= 2 ? lang[..2] : lang).ToUpperInvariant();
                using var f = new Font("Segoe UI", 12, FontStyle.Bold, GraphicsUnit.Pixel);
                using var fb = new SolidBrush(Color.White);
                var sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center };
                g.DrawString(code, f, fb, new RectangleF(r.X, r.Y, r.Width, r.Height), sf);
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

    private static readonly Dictionary<string, Bitmap?> FlagImages = new();

    private static Bitmap? FlagImage(string lang)
    {
        if (FlagImages.TryGetValue(lang, out var cached)) return cached;
        Bitmap? img = null;
        try
        {
            using var s = typeof(TrayApp).Assembly.GetManifestResourceStream($"{lang}.png");
            if (s is not null) img = new Bitmap(s);
        }
        catch { /* no embedded flag for this language */ }
        FlagImages[lang] = img;
        return img;
    }

    public void Dispose()
    {
        _poll.Dispose();
        _icon.Dispose();
        foreach (var ic in _flags.Values) ic.Dispose();
    }
}

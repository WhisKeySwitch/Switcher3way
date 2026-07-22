using System.Drawing;
using System.IO;
using System.Windows.Forms;
using Microsoft.Win32;

namespace Switcher3way.App;

/// <summary>
/// Built-in Help window: renders the bundled user guide (in the UI language, else English) inside
/// the app with a WebBrowser control — offline, no external browser link. Mirrors the macOS in-app
/// Help window. The "also available in" links switch language in place; real http links open in
/// the default browser; in-page anchors (the table of contents) scroll within the page.
/// </summary>
internal sealed class HelpWindow : Form
{
    private readonly WebBrowser _web = new()
    {
        Dock = DockStyle.Fill,
        IsWebBrowserContextMenuEnabled = false,
        AllowWebBrowserDrop = false,
        ScriptErrorsSuppressed = true,
        WebBrowserShortcutsEnabled = false,
    };
    private string _lang;

    // MSHTML hosts the WebBrowser in IE7 document mode by default; opt this process into IE11 so the
    // guide's CSS renders correctly. Static ctor runs before the first instance's _web is created.
    static HelpWindow() => EnableModernRendering();

    public HelpWindow(string lang)
    {
        _lang = lang;
        Text = "Switcher3way — " + Loc.T("menu.help");
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(720, 640);
        MinimumSize = new Size(420, 320);
        try { Icon = Icon.ExtractAssociatedIcon(Environment.ProcessPath!); } catch { /* dev host */ }

        _web.Navigating += OnNavigating;
        Controls.Add(_web);
        Load += (_, _) => _web.DocumentText = HelpContent.Render(_lang);
    }

    private void OnNavigating(object? sender, WebBrowserNavigatingEventArgs e)
    {
        var url = e.Url?.ToString() ?? "";

        if (url.StartsWith("help:", StringComparison.OrdinalIgnoreCase)) // in-app language switch
        {
            e.Cancel = true;
            _lang = url["help:".Length..];
            _web.DocumentText = HelpContent.Render(_lang);
            return;
        }

        if (url.StartsWith("http://", StringComparison.OrdinalIgnoreCase) ||
            url.StartsWith("https://", StringComparison.OrdinalIgnoreCase)) // external → default browser
        {
            e.Cancel = true;
            try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(url) { UseShellExecute = true }); }
            catch { /* best-effort */ }
        }
        // else: about:blank (initial content) and in-page #anchors proceed normally
    }

    private static void EnableModernRendering()
    {
        try
        {
            var exe = Path.GetFileName(Environment.ProcessPath);
            if (string.IsNullOrEmpty(exe)) return;
            using var k = Registry.CurrentUser.CreateSubKey(
                @"Software\Microsoft\Internet Explorer\Main\FeatureControl\FEATURE_BROWSER_EMULATION");
            if (k?.GetValue(exe) is null) k?.SetValue(exe, 11001, RegistryValueKind.DWord); // 11001 = IE11 edge mode
        }
        catch { /* best-effort; falls back to the default document mode */ }
    }
}

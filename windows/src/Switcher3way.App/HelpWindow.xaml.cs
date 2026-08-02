using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.Web.WebView2.Core;
using Windows.Graphics;

namespace Switcher3way.App;

/// <summary>
/// Built-in help: the bundled user guide rendered offline in a WebView2, with a table of contents
/// built from the guide's own section headings and EN/УК/РУ pills to switch language in place.
/// External links open in the default browser. If WebView2 is unavailable the window explains itself
/// instead of showing an empty pane.
/// </summary>
public sealed partial class HelpWindow : Window
{
    private string _lang;
    private bool _ready;

    public HelpWindow(string lang)
    {
        _lang = Normalize(lang);
        this.InitializeComponent();
        AppWindow.Resize(new SizeInt32(900, 700));
        AppWindow.IsShownInSwitchers = true;

        BuildToc();
        _ = LoadAsync();
    }

    /// <summary>The guide exists in these three languages; anything else reads the English one.</summary>
    private static string Normalize(string lang) => lang is "uk" or "ru" ? lang : "en";

    private void BuildToc() => SectionList.ItemsSource = HelpContent.Sections(_lang);

    private async Task LoadAsync()
    {
        try
        {
            await View.EnsureCoreWebView2Async();
            var core = View.CoreWebView2;
            core.Settings.AreDevToolsEnabled = false;
            core.Settings.AreDefaultContextMenusEnabled = false;
            core.Settings.IsZoomControlEnabled = true;
            _ready = true;
            View.NavigateToString(HelpContent.Render(_lang));
        }
        catch (Exception ex)
        {
            Diagnostics.Log("help: WebView2 unavailable — " + ex.Message);
            View.Visibility = Visibility.Collapsed;
            FallbackText.Visibility = Visibility.Visible;
            FallbackText.Text = "The help viewer needs the Microsoft Edge WebView2 runtime, which " +
                                "isn't available on this system. The same guide is online at " +
                                "github.com/WhisKeySwitch/Switcher3way (docs/user-guide.md).";
        }
    }

    private void Section_Click(object sender, RoutedEventArgs e)
    {
        if (!_ready || sender is not Button b || b.Tag is not string anchor) return;
        // Scroll the rendered guide to that heading (anchors come from HelpContent's slugs).
        var js = $"(function(){{var e=document.getElementById({Quote(anchor)});if(e)e.scrollIntoView({{behavior:'smooth'}});}})()";
        _ = View.ExecuteScriptAsync(js);
    }

    private void Lang_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button b || b.Tag is not string lang) return;
        _lang = Normalize(lang);
        BuildToc();
        if (_ready) View.NavigateToString(HelpContent.Render(_lang));
    }

    /// <summary>Real links go to the browser; the in-page navigation we trigger ourselves stays.</summary>
    private void View_NavigationStarting(WebView2 sender, CoreWebView2NavigationStartingEventArgs args)
    {
        var uri = args.Uri ?? "";
        if (uri.StartsWith("http://", StringComparison.OrdinalIgnoreCase) ||
            uri.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
        {
            args.Cancel = true;
            Launch.Open(uri);
        }
    }

    private static string Quote(string s) => "'" + s.Replace("\\", "\\\\").Replace("'", "\\'") + "'";
}

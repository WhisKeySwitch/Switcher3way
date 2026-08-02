using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.Graphics;

namespace Switcher3way.App;

/// <summary>
/// The update prompt — "Switcher3way X is available", the release notes rendered as headings and
/// bullets (never raw markup), and Install / Later / Skip. Also serves the plain
/// "you're up to date" and error messages, so a tray-only app needs no XamlRoot host for a dialog.
/// </summary>
public sealed partial class UpdatePromptWindow : Window
{
    private Action? _onInstall, _onSkip;

    private UpdatePromptWindow()
    {
        this.InitializeComponent();
        var presenter = OverlappedPresenter.CreateForDialog();
        presenter.IsAlwaysOnTop = true;
        AppWindow.SetPresenter(presenter);
        AppWindow.IsShownInSwitchers = false;
    }

    /// <summary>Offer an available update.</summary>
    internal static void ShowUpdate(UpdateInfo info, string current, Action onInstall, Action onSkip)
    {
        var w = new UpdatePromptWindow
        {
            _onInstall = onInstall,
            _onSkip = onSkip,
        };
        w.TitleText.Text = Loc.Tf("update.available.title", info.Version);
        w.SubtitleText.Text = Loc.Tf("update.installed", current) + " " + "The app restarts itself to finish.";
        w.NotesHeader.Text = "WHAT'S NEW";
        w.RenderNotes(info.Notes);
        w.InstallButton.Content = Loc.T("update.install");
        w.LaterButton.Content = Loc.T("update.later");
        w.SkipButton.Content = Loc.T("update.skip");
        w.Show(420, 380);
    }

    /// <summary>A plain informational message (up to date, or a failure).</summary>
    public static void ShowMessage(string title, string body)
    {
        var w = new UpdatePromptWindow();
        w.TitleText.Text = title;
        w.SubtitleText.Text = body;
        w.NotesCard.Visibility = Visibility.Collapsed;
        w.InstallButton.Content = "OK";
        w.LaterButton.Visibility = Visibility.Collapsed;
        w.SkipButton.Visibility = Visibility.Collapsed;
        w._onInstall = null;                       // OK just closes
        w.Show(420, 190);
    }

    private void Show(int width, int height)
    {
        double scale = GetScale();
        AppWindow.Resize(new SizeInt32((int)(width * scale), (int)(height * scale)));
        Activate();
        Native.SetForegroundWindow(WinRT.Interop.WindowNative.GetWindowHandle(this));
    }

    private double GetScale()
    {
        try { return AppWindow.Id.Value == 0 ? 1 : 1; } catch { return 1; }
    }

    /// <summary>
    /// Render the release notes: "## heading" lines become bold headings, "- item" lines become
    /// bulleted rows, everything else a paragraph. Raw markup must never reach the user.
    /// </summary>
    private void RenderNotes(string? notes)
    {
        NotesList.Children.Clear();
        foreach (var raw in (notes ?? "").Replace("\r\n", "\n").Split('\n'))
        {
            var line = raw.Trim();
            if (line.Length == 0) continue;

            if (line.StartsWith('#'))
            {
                var text = line.TrimStart('#', ' ');
                if (text.Equals("What's new", StringComparison.OrdinalIgnoreCase)) continue; // already the card header
                NotesList.Children.Add(new TextBlock
                {
                    Text = text, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
                    FontSize = 13, Margin = new Thickness(0, 4, 0, 0), TextWrapping = TextWrapping.Wrap,
                });
                continue;
            }

            bool bullet = line.StartsWith("- ") || line.StartsWith("* ");
            var body = bullet ? line[2..].Trim() : line;
            body = body.Replace("**", "").Replace("`", "");     // strip the emphasis markers we don't render

            if (!bullet)
            {
                NotesList.Children.Add(new TextBlock { Text = body, FontSize = 13, TextWrapping = TextWrapping.Wrap });
                continue;
            }

            var row = new Grid { ColumnSpacing = 9 };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            var dot = new TextBlock
            {
                Text = "•", FontSize = 13,
                Foreground = (Brush)Application.Current.Resources["AccentTextFillColorPrimaryBrush"],
            };
            var text2 = new TextBlock { Text = body, FontSize = 13, TextWrapping = TextWrapping.Wrap, LineHeight = 19 };
            Grid.SetColumn(text2, 1);
            row.Children.Add(dot);
            row.Children.Add(text2);
            NotesList.Children.Add(row);
        }
    }

    private void Install_Click(object s, RoutedEventArgs e) { var a = _onInstall; Close(); a?.Invoke(); }
    private void Later_Click(object s, RoutedEventArgs e) => Close();
    private void Skip_Click(object s, RoutedEventArgs e) { var a = _onSkip; Close(); a?.Invoke(); }
}

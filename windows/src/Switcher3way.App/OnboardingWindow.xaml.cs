using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Switcher3way.Core;
using Switcher3way.Dictionaries;
using Windows.Graphics;

namespace Switcher3way.App;

/// <summary>One detected keyboard layout, as shown on the onboarding "Your layouts" step.</summary>
public sealed class LayoutRow
{
    public string Name { get; init; } = "";
    public string Mechanical { get; init; } = "";
    public ImageSource? Flag { get; init; }
    public string PillText { get; init; } = "";
    public Brush? PillBackground { get; init; }
    public Brush? PillForeground { get; init; }
}

/// <summary>
/// First-run setup: what the app does, which layouts were found (and whether their dictionaries are
/// available), and which key triggers a manual conversion — with a live try-it box that runs the real
/// detector on what you type. Shown once; finishing sets <c>HasCompletedOnboarding</c>.
///
/// No permission grants are needed on Windows, so this flow exists to explain the app and get the
/// trigger chosen rather than to unlock anything.
/// </summary>
public sealed partial class OnboardingWindow : Window
{
    private readonly SettingsManager _s;
    private readonly Action _onFinished;
    private readonly Win32LayoutCatalog _catalog = new();
    private readonly NWayResolver _resolver;
    private int _step = 1;

    internal OnboardingWindow(SettingsManager s, Action onFinished)
    {
        _s = s;
        _onFinished = onFinished;
        _resolver = new NWayResolver(_catalog, new HunspellDictionaryValidator(), new EmptyAlwaysConvert());
        this.InitializeComponent();

        var presenter = OverlappedPresenter.CreateForDialog();
        presenter.IsResizable = false;
        AppWindow.SetPresenter(presenter);
        AppWindow.Resize(new SizeInt32(560, 620));

        if (Environment.ProcessPath is string exe) AppIcon.Source = AppInfo.Icon(exe);
        BuildLayoutRows();
        UpdateTryLabel();
        ShowStep(1);
    }

    // ---- steps ------------------------------------------------------------------------------
    private void ShowStep(int step)
    {
        _step = step;
        Step1.Visibility = step == 1 ? Visibility.Visible : Visibility.Collapsed;
        Step2.Visibility = step == 2 ? Visibility.Visible : Visibility.Collapsed;
        Step3.Visibility = step == 3 ? Visibility.Visible : Visibility.Collapsed;

        BackButton.Visibility = step == 1 ? Visibility.Collapsed : Visibility.Visible;
        NextButton.Content = step switch { 1 => "Get started", 2 => "Next", _ => "Finish" };

        var on = (Brush)Application.Current.Resources["AccentFillColorDefaultBrush"];
        var off = new SolidColorBrush(Colors.Gray) { Opacity = 0.45 };
        Dot1.Fill = step == 1 ? on : off;
        Dot2.Fill = step == 2 ? on : off;
        Dot3.Fill = step == 3 ? on : off;
    }

    private void Back_Click(object s, RoutedEventArgs e) => ShowStep(Math.Max(1, _step - 1));

    private void Next_Click(object s, RoutedEventArgs e)
    {
        if (_step < 3) { ShowStep(_step + 1); return; }
        Finish();
    }

    private void Finish()
    {
        ApplyTrigger();
        StartupShortcut.Set(StartupCheck.IsChecked == true);
        _s.HasCompletedOnboarding = true;
        _s.Save();
        _onFinished();
        Close();
    }

    // ---- step 2: detected layouts ------------------------------------------------------------
    private void BuildLayoutRows()
    {
        var dict = new HunspellDictionaryValidator();
        var success = (Brush)Application.Current.Resources["SystemFillColorSuccessBackgroundBrush"];
        var successText = (Brush)Application.Current.Resources["SystemFillColorSuccessBrush"];
        var caution = (Brush)Application.Current.Resources["SystemFillColorCautionBackgroundBrush"];
        var cautionText = (Brush)Application.Current.Resources["SystemFillColorCautionBrush"];

        var rows = new List<LayoutRow>();
        foreach (var l in _catalog.InstalledLayouts())
        {
            var lang = l.Lang ?? "?";
            bool ready = l.Lang is not null && dict.IsAvailable(l.Lang);
            rows.Add(new LayoutRow
            {
                Name = LayoutStatus.LangName(lang),
                Mechanical = lang switch { "en" => "QWERTY", "uk" or "ru" or "be" => "ЙЦУКЕН", _ => "" },
                Flag = FlagIcon.Image(lang),
                PillText = ready ? "Dictionary ready" : "No dictionary — skipped",
                PillBackground = ready ? success : caution,
                PillForeground = ready ? successText : cautionText,
            });
        }
        LayoutList.ItemsSource = rows;
    }

    // ---- step 3: trigger + live try-it -------------------------------------------------------
    private (int Vk, bool Double) SelectedTrigger()
    {
        if (TrigPause.IsChecked == true) return (0x13, false);
        if (TrigF9.IsChecked == true) return (0x78, false);
        return (0x11, true);   // double Ctrl — the default
    }

    private void ApplyTrigger()
    {
        var (vk, dbl) = SelectedTrigger();
        _s.TriggerKey = vk;
        _s.TriggerDoubleTap = dbl;
    }

    private void Trigger_Checked(object s, RoutedEventArgs e)
    {
        if (TryLabel is null) return;      // fires during XAML load, before the rest exists
        UpdateTryLabel();
        Evaluate();
    }

    private void UpdateTryLabel()
    {
        var (vk, dbl) = SelectedTrigger();
        var label = (vk, dbl) switch { (0x13, _) => "Pause/Break", (0x78, _) => "F9", _ => "Ctrl twice" };
        TryLabel.Text = $"Try it — type a word in the wrong layout, then tap {label}";
    }

    private void TryBox_TextChanged(object s, TextChangedEventArgs e) => Evaluate();

    /// <summary>
    /// Run the real detector over what was typed: map the characters back to keystrokes through the
    /// active layout, then ask the resolver what it would convert them to. This is the same path the
    /// manual trigger uses on a selection, so what we promise here is what the app will do.
    /// </summary>
    private void Evaluate()
    {
        var text = TryBox.Text.Trim();
        if (text.Length == 0) { TryResult.Text = ""; return; }

        try
        {
            var current = _catalog.InstalledLayouts().FirstOrDefault(l => l.Id == _catalog.CurrentLayoutId());
            if (current is null) { TryResult.Text = ""; return; }

            var map = _catalog.ReverseMap(current);
            var keys = new List<TypedKey>(text.Length);
            foreach (var ch in text)
            {
                if (!map.TryGetValue(ch, out var k)) { TryResult.Text = ""; return; }
                keys.Add(k);
            }

            var plan = _resolver.ManualPlan(keys, capsLock: false, preferredAmbiguityLang: _s.AmbiguousLang);
            var best = plan?.Candidates.FirstOrDefault();
            TryResult.Text = best is null
                ? "That already looks right — nothing to convert."
                : $"Nice — that would become {best.Converted}";
        }
        catch (Exception ex)
        {
            Diagnostics.Log("onboarding try-it failed: " + ex.Message);
            TryResult.Text = "";
        }
    }
}

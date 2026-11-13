using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Windows.Graphics;

namespace Switcher3way.App;

/// <summary>
/// The app's own ask — "Enjoying Switcher3way?" — with Rate it / Not now / No thanks. Modelled on
/// <see cref="UpdatePromptWindow"/>, which is how this app shows a dialog at all: it has no main
/// window to host a <c>ContentDialog</c>.
///
/// The preamble exists because Microsoft's rating dialog cannot carry an opt-out. Without a window of
/// our own in front of it, there is no click that means "never ask me again" — only "close", which is
/// indistinguishable from "later". It is also the owner window the Store dialog needs (see
/// <see cref="ReviewPrompt"/>), so a tray app needs it either way.
///
/// Closing with the title-bar X is read as a deferral, the forgiving reading: a user who dismisses a
/// window has not said "never".
/// </summary>
public sealed partial class RateWindow : Window
{
    private Action? _onRate, _onDefer, _onDecline;
    private bool _answered;

    private RateWindow()
    {
        this.InitializeComponent();
        var presenter = OverlappedPresenter.CreateForDialog();
        presenter.IsAlwaysOnTop = true;
        AppWindow.SetPresenter(presenter);
        AppWindow.IsShownInSwitchers = false;

        Closed += (_, _) => { if (!_answered) { _answered = true; _onDefer?.Invoke(); } };
    }

    /// <param name="conversions">
    /// How many words the app has fixed, so the ask can say what it is asking about. A prompt that
    /// states what it did for you is a different thing from one that just wants stars.
    /// </param>
    internal static RateWindow Show(int conversions, Action onRate, Action onDefer, Action onDecline)
    {
        var w = new RateWindow { _onRate = onRate, _onDefer = onDefer, _onDecline = onDecline };
        w.TitleText.Text = Loc.T("review.title");
        w.SubtitleText.Text = Loc.T("review.subtitle");
        w.BodyText.Text = Loc.Tf("review.body", conversions);
        w.RateButton.Content = Loc.T("review.rate");
        w.LaterButton.Content = Loc.T("review.later");
        w.NeverButton.Content = Loc.T("review.never");

        // Tall enough that the star row holding the card is never squeezed out by the Auto rows —
        // 260 was, and the symptom is an empty card rather than a cramped one.
        w.AppWindow.Resize(new SizeInt32(420, 340));
        w.Activate();
        Native.SetForegroundWindow(WinRT.Interop.WindowNative.GetWindowHandle(w));
        return w;
    }

    private void Answer(Action? a) { _answered = true; Close(); a?.Invoke(); }

    /// <summary>
    /// "Rate it" must NOT close this window: the Store's dialog is parented to it, and a parent that
    /// closes first leaves the dialog with no owner — which is one of the two ways this API fails
    /// invisibly. <see cref="ReviewPrompt"/> closes the window once the Store call has returned.
    /// </summary>
    private void Rate_Click(object s, RoutedEventArgs e)
    {
        _answered = true;
        RateButton.IsEnabled = LaterButton.IsEnabled = NeverButton.IsEnabled = false;
        _onRate?.Invoke();
    }

    /// <summary>Close once the Store dialog is done with us as its owner.</summary>
    internal void DismissAfterStoreDialog()
    {
        _answered = true;   // the deferral on Closed must not fire: the user rated
        Close();
    }

    private void Later_Click(object s, RoutedEventArgs e) => Answer(_onDefer);
    private void Never_Click(object s, RoutedEventArgs e) => Answer(_onDecline);
}

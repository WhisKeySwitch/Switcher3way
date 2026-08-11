using Microsoft.Windows.AppNotifications;
using Microsoft.Windows.AppNotifications.Builder;

namespace Switcher3way.App;

/// <summary>
/// Windows notifications for the two things the app cannot say any other way: a rewrite it could not
/// perform, and an offer to remember a word after the user undoes a conversion. Everything else the app
/// does is visible where it happens (the caret chip, the tray icon), so this is deliberately limited —
/// a layout fixer that toasts on success would be unusable.
///
/// Registration covers both flavours, but by opposite mechanisms, and that difference cost a Store
/// certification cycle. Unpackaged, <c>AppNotificationManager.Register()</c> creates the COM activator
/// and identity the process lacks. Packaged, it *looks its activator up* under
/// <c>HKLM\SOFTWARE\Classes\PackagedCom\Package\{PFN}\Class</c> and throws if the manifest never
/// declared one — so the two <c>windows.toastNotificationActivation</c> / <c>windows.comServer</c>
/// extensions in <c>Package.appxmanifest</c> are what keep notifications alive in the Store build. If
/// registration fails the app carries on — a failure here must never stop the tray from working — which
/// is why the trigger's feedback also has an on-screen surface that needs none of this
/// (<see cref="CaretChip.ShowMessage"/>).
/// </summary>
internal static class Toast
{
    private const string ActionKey = "action";
    private const string WordKey = "word";
    private const string NeverConvertAction = "never";

    private static Action<string>? _onNeverConvert;
    private static bool _registered;
    private static bool _suppressionLogged;

    /// <param name="onNeverConvert">
    /// Called with the word to add to the never-convert list. The callback arrives on a notification
    /// thread, so the caller is responsible for marshalling to the UI thread before touching settings.
    /// </param>
    public static void Initialize(Action<string> onNeverConvert)
    {
        _onNeverConvert = onNeverConvert;
        try
        {
            AppNotificationManager.Default.NotificationInvoked += OnInvoked;
            AppNotificationManager.Default.Register();
            _registered = true;
            Diagnostics.Log("toast: registered");
        }
        catch (Exception ex)
        {
            // Ungated: if notifications are dead the user only ever sees silence, so the reason has to
            // be recoverable from the log even with debug logging off.
            Diagnostics.LogAlways("toast: registration failed, notifications disabled: " + ex.Message);
        }
    }

    public static void Shutdown()
    {
        if (!_registered) return;
        try { AppNotificationManager.Default.Unregister(); }
        catch (Exception ex) { Diagnostics.Log("toast: unregister failed: " + ex.Message); }
    }

    /// <summary>A failure the user would otherwise experience as the app silently doing nothing.</summary>
    public static void ShowError(string message)
    {
        Show(new AppNotificationBuilder()
            .AddText(Loc.T("toast.error.title"))
            .AddText(message));
    }

    /// <summary>
    /// The trigger was pressed and there was nothing to do — no second layout, nothing typed, nothing
    /// convertible. Not an error, but it must be visible: silence here is indistinguishable from a
    /// broken app, and Store certification rejected the app for exactly that.
    /// </summary>
    public static void ShowHint(string title, string message)
    {
        Show(new AppNotificationBuilder()
            .AddText(title)
            .AddText(message));
    }

    /// <summary>
    /// After an undo: offer to leave this word alone in future. The word carried in the button argument
    /// is the *converted* form, which is what the never-convert rule matches on, so accepting suppresses
    /// exactly this conversion rather than every conversion of the same keystrokes.
    /// </summary>
    public static void OfferNeverConvert(string original, string converted)
    {
        if (string.IsNullOrWhiteSpace(converted)) return;
        Show(new AppNotificationBuilder()
            .AddText(Loc.T("toast.undo.title"))
            .AddText(Loc.Tf("toast.undo.body", converted, original))
            .AddButton(new AppNotificationButton(Loc.T("toast.undo.never"))
                .AddArgument(ActionKey, NeverConvertAction)
                .AddArgument(WordKey, converted)));
    }

    private static void Show(AppNotificationBuilder builder)
    {
        if (!_registered)
        {
            // Ungated and once: registration failing is already logged, but without this the log shows no
            // trace of the notifications that were then dropped, and "the app said nothing" reads as a
            // decision rather than a failure. That gap is what let a packaged build ship with every
            // notification discarded.
            if (!_suppressionLogged)
            {
                _suppressionLogged = true;
                Diagnostics.LogAlways("toast: not registered — this and any further notifications are dropped");
            }
            return;
        }
        try { AppNotificationManager.Default.Show(builder.BuildNotification()); }
        catch (Exception ex) { Diagnostics.Log("toast: show failed: " + ex.Message); }
    }

    private static void OnInvoked(AppNotificationManager sender, AppNotificationActivatedEventArgs args)
    {
        try
        {
            if (!args.Arguments.TryGetValue(ActionKey, out var action) || action != NeverConvertAction) return;
            if (!args.Arguments.TryGetValue(WordKey, out var word) || string.IsNullOrWhiteSpace(word)) return;
            Diagnostics.Log($"toast: never-convert accepted for \"{word}\"");
            _onNeverConvert?.Invoke(word);
        }
        catch (Exception ex)
        {
            Diagnostics.Log("toast: activation handling failed: " + ex.Message);
        }
    }
}

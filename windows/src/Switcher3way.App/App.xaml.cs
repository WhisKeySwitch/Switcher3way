using System.IO;
using Microsoft.UI.Xaml;

namespace Switcher3way.App;

/// <summary>
/// WinUI 3 application entry. Creates the system-tray presence (which owns the <see cref="Engine"/>);
/// settings, help, update, feedback and onboarding surfaces are added as they are ported. Tray-only —
/// there is no main window.
/// </summary>
public partial class App : Application
{
    private Tray? _tray;
    private Window? _keepAlive;

    public App() => this.InitializeComponent();

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        // Diagnostics for the migration: catch everything we can so a crash leaves a trace.
        this.UnhandledException += (_, e) => { Log("UnhandledException: " + e.Exception); e.Handled = true; };
        AppDomain.CurrentDomain.UnhandledException += (_, e) => Log("AppDomain: " + e.ExceptionObject);
        TaskScheduler.UnobservedTaskException += (_, e) => { Log("Task: " + e.Exception); e.SetObserved(); };
        try
        {
            // WinUI ends the message loop once the last window closes, which for a tray-first app means
            // the process dies the moment the user closes Settings — or, on a fresh install, the moment
            // they press Finish in the welcome flow. This window is never activated, so it never shows;
            // it exists only to keep the loop running. "Quit" calls Application.Exit(), which ignores it.
            _keepAlive = new Window();
            _tray = new Tray();
            // Diagnostic hook: `Switcher3way.exe diagui` exercises the XAML surfaces at startup so a
            // shipped build that can't open windows reports why, instead of just looking half-dead.
            var args2 = Environment.GetCommandLineArgs();
            if (args2.Any(a => a.Equals("diagui", StringComparison.OrdinalIgnoreCase)))
            {
                Diagnostics.LogAlways("diagui: opening Settings…");
                _tray.OpenSettings();
                Diagnostics.LogAlways("diagui: done");
            }
            // The notification paths need a failed rewrite or an undo to happen naturally, neither of
            // which can be provoked with synthetic input (the hook ignores it). These show them on
            // demand — separately, because Windows only surfaces one toast at a time and queues the rest.
            if (args2.Any(a => a.Equals("diagtoast", StringComparison.OrdinalIgnoreCase)))
            {
                Diagnostics.LogAlways("diagtoast: error notification…");
                Toast.ShowError(Loc.T("notify.protected"));
            }
            if (args2.Any(a => a.Equals("diagtoastoffer", StringComparison.OrdinalIgnoreCase)))
            {
                Diagnostics.LogAlways("diagtoastoffer: remember-word notification…");
                Toast.OfferNeverConvert("ghbdsn", "привіт");
            }
            // Which source the chip's position comes from, probed repeatedly so focus can be moved
            // between apps while it runs — the chip itself only appears after a real conversion, which
            // synthetic input cannot trigger.
            if (args2.Any(a => a.Equals("diagcaret", StringComparison.OrdinalIgnoreCase)))
            {
                var probe = Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread().CreateTimer();
                int left = 15;
                probe.Interval = TimeSpan.FromSeconds(2);
                probe.Tick += (t, _) =>
                {
                    CaretChip.Probe();
                    if (--left <= 0) t.Stop();
                };
                probe.Start();
                Diagnostics.LogAlways("diagcaret: probing every 2s for 30s — move focus between apps");
            }
            // The trigger's "nothing to do" feedback. The trigger itself cannot be pressed synthetically
            // (it is swallowed as a control key), so this shows what the reviewer's machine would show.
            if (args2.Any(a => a.Equals("diaghint", StringComparison.OrdinalIgnoreCase)))
            {
                Diagnostics.LogAlways("diaghint: showing the one-layout hint…");
                // Through Tray, not Toast directly: the point of this switch is to prove what the
                // reviewer's machine shows, and that is now two surfaces. Calling Toast here is how the
                // 0.2.6 hint got verified while the chip — and, in the packaged build, the notification
                // itself — went untested.
                _tray.ShowHint(Loc.T("hint.setup.title"), Loc.T("hint.setup.body"), Loc.T("hint.setup.chip"));
            }
            // One rewrite against the focused window, with the injection timing under the caller's
            // control, so the cause of the cycling corruption can be isolated instead of guessed at.
            // The two suspects — the erase burst going out with no delay, and the layout switch landing
            // immediately before the insert — are varied independently here.
            //
            //   diagrewrite <eraseCount> <eraseMs> <settleMs> <charMs> [none|same|cross]
            //
            // Types a rotating a–z marker of the same length, so a corrupted run is legible on sight:
            // the shipped failure replaces a run with the character that follows it.
            var dr = args2.ToList().FindIndex(a => a.Equals("diagrewrite", StringComparison.OrdinalIgnoreCase));
            if (dr >= 0)
            {
                int Arg(int i, int dflt) =>
                    dr + i < args2.Length && int.TryParse(args2[dr + i], out var v) ? v : dflt;
                int count = Arg(1, 46), eraseMs = Arg(2, 0), settleMs = Arg(3, 15), charMs = Arg(4, 2);
                string layout = dr + 5 < args2.Length ? args2[dr + 5].ToLowerInvariant() : "none";

                var marker = new string(Enumerable.Range(0, count).Select(i => (char)('a' + i % 26)).ToArray());
                var timer = Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread().CreateTimer();
                timer.Interval = TimeSpan.FromMilliseconds(2500);   // time to focus the target window
                timer.IsRepeating = false;
                timer.Tick += (_, _) =>
                {
                    if (layout != "none")
                    {
                        // "cross" = switch to a Latin layout, "same" = to a different Cyrillic one, so a
                        // change of script can be told apart from a change of layout.
                        var cat = new Win32LayoutCatalog();
                        var cur = cat.CurrentLayoutId();
                        var target = cat.InstalledLayouts().FirstOrDefault(l =>
                            l.Id != cur && (layout == "cross" ? l.Lang == "en" : l.Lang is "uk" or "ru"));
                        if (target is null) Diagnostics.LogAlways($"diagrewrite: no '{layout}' layout installed — skipping switch");
                        else Diagnostics.LogAlways($"diagrewrite: layout {cur} -> {target.Id} ({target.Lang}) via {LayoutSwitcher.SwitchForeground(target.Id)}");
                    }
                    Diagnostics.LogAlways($"diagrewrite: erase={count} eraseMs={eraseMs} settleMs={settleMs} " +
                                          $"charMs={charMs} layout={layout}");
                    Diagnostics.LogAlways($"diagrewrite: intended={marker}");
                    var res = TextRewriter.Rewrite(count, marker,
                                                   pace: new TextRewriter.Pace(eraseMs, settleMs, charMs));
                    Diagnostics.LogAlways($"diagrewrite: result={res}");
                };
                timer.Start();
            }
            // Password-field detection, probed live. This exists because the guard shipped broken for four
            // releases on an untested assumption: focus a real password field and read the answer.
            if (args2.Any(a => a.Equals("diagpw", StringComparison.OrdinalIgnoreCase)))
            {
                var probe = Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread().CreateTimer();
                int left = 15;
                probe.Interval = TimeSpan.FromSeconds(2);
                probe.Tick += (t, _) =>
                {
                    Diagnostics.LogAlways($"diagpw[ui]:     {SecureField.Describe()}");
                    // The real guard runs on the Engine's worker thread, not here. UIA is
                    // apartment-sensitive, so a UI-thread-only check can pass while production fails.
                    System.Threading.Tasks.Task.Run(() =>
                        Diagnostics.LogAlways($"diagpw[worker]: {SecureField.Describe()}"));
                    if (--left <= 0) t.Stop();
                };
                probe.Start();
                Diagnostics.LogAlways("diagpw: probing every 2s for 30s — focus a password field");
            }
            // Same probe, but against our own WinUI text box: it has no classic caret, so it exercises the
            // accessibility tiers the way Chrome and Electron do, without needing to steal the foreground.
            if (args2.Any(a => a.Equals("diagcaretwinui", StringComparison.OrdinalIgnoreCase)))
            {
                _tray.OpenSettings();
                var probe = Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread().CreateTimer();
                int left = 6;
                probe.Interval = TimeSpan.FromSeconds(2);
                probe.Tick += (t, _) =>
                {
                    CaretChip.Probe(_tray?.DiagFocusSettingsSearch() ?? IntPtr.Zero);
                    if (--left <= 0) t.Stop();
                };
                probe.Start();
                Diagnostics.LogAlways("diagcaretwinui: probing our own WinUI text box…");
            }
        }
        catch (Exception ex)
        {
            Log("OnLaunched: " + ex);
        }
    }

    private static void Log(string s)
    {
        try { File.AppendAllText(Path.Combine(Path.GetTempPath(), "s3w-winui-error.log"), $"{DateTime.Now:HH:mm:ss} {s}\n\n"); }
        catch { /* best-effort */ }
    }
}

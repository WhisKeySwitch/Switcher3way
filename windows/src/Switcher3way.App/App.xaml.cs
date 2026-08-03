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
            if (Environment.GetCommandLineArgs().Any(a => a.Equals("diagui", StringComparison.OrdinalIgnoreCase)))
            {
                Diagnostics.LogAlways("diagui: opening Settings…");
                _tray.OpenSettings();
                Diagnostics.LogAlways("diagui: done");
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

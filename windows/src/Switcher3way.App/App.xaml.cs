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

    public App() => this.InitializeComponent();

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        // Diagnostics for the migration: catch everything we can so a crash leaves a trace.
        this.UnhandledException += (_, e) => { Log("UnhandledException: " + e.Exception); e.Handled = true; };
        AppDomain.CurrentDomain.UnhandledException += (_, e) => Log("AppDomain: " + e.ExceptionObject);
        TaskScheduler.UnobservedTaskException += (_, e) => { Log("Task: " + e.Exception); e.SetObserved(); };
        try
        {
            _tray = new Tray();
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

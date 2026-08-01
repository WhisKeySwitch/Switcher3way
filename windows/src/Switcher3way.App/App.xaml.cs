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
        _tray = new Tray();
    }
}

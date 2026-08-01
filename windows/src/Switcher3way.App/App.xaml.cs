using Microsoft.UI.Xaml;

namespace Switcher3way.App;

/// <summary>
/// WinUI 3 application entry. Owns the <see cref="Engine"/> and (as surfaces are ported) the tray,
/// settings, help, update, feedback and onboarding windows. Phase 0 skeleton: starts the engine and
/// shows a placeholder window; the WinForms surfaces are being reintroduced one at a time.
/// </summary>
public partial class App : Application
{
    private Window? _window;
    private SettingsManager? _settings;
    private Engine? _engine;

    public App() => this.InitializeComponent();

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        _settings = SettingsManager.Load();
        Loc.Configure(_settings.InterfaceLanguage);

        _engine = new Engine(_settings);
        _engine.Notify += m => Diagnostics.Log($"notify: {m}");
        _engine.Start();

        _window = new MainWindow();
        _window.Activate();
    }
}

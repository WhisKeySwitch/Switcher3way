using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;

namespace Switcher3way.App;

/// <summary>
/// One row in the exceptions list (an excluded app, or a never/always-convert word). Public with
/// public properties so classic XAML {Binding} can reach it. Visibility is exposed directly to keep
/// the template converter-free.
/// </summary>
public sealed class ExceptionRow
{
    /// <summary>The value stored in settings (exe name, or the word).</summary>
    public string Value { get; init; } = "";
    /// <summary>Primary label — friendly app name, or the word itself.</summary>
    public string Display { get; init; } = "";
    /// <summary>Secondary label — the .exe file name for apps; empty for words.</summary>
    public string Sub { get; init; } = "";
    public ImageSource? Icon { get; init; }
    /// <summary>Built-in password managers: shown locked, never removable.</summary>
    public bool IsProtected { get; init; }

    /// <summary>Localized "always off" marker shown on protected rows.</summary>
    public string LockedText => Loc.T("settings.exceptions.alwaysOff");

    public Visibility LockedVisibility => IsProtected ? Visibility.Visible : Visibility.Collapsed;
    public Visibility RemoveVisibility => IsProtected ? Visibility.Collapsed : Visibility.Visible;
    public Visibility IconVisibility => Icon is null ? Visibility.Collapsed : Visibility.Visible;
    public Visibility SubVisibility => Sub.Length == 0 ? Visibility.Collapsed : Visibility.Visible;
}

using Microsoft.UI.Xaml.Markup;

namespace Switcher3way.App;

/// <summary>
/// XAML markup extension for interface strings: <c>Text="{local:Loc Key=settings.autoSwitch}"</c>.
/// Resolves through <see cref="Loc"/> (16 languages, English fallback) at load time — so a change of
/// interface language reloads the window rather than re-binding.
///
/// Only use keys that exist in <see cref="Loc"/>; an unknown key renders as the key itself.
/// </summary>
[MarkupExtensionReturnType(ReturnType = typeof(string))]
public sealed class LocExtension : MarkupExtension
{
    public string Key { get; set; } = "";

    protected override object ProvideValue() => Loc.T(Key);
}

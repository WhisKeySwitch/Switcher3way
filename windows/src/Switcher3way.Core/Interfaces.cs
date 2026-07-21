namespace Switcher3way.Core;

/// <summary>
/// Offline word validation for a language. On Windows this is backed by bundled Hunspell
/// dictionaries; the macOS app uses NSSpellChecker. The core only needs these two questions.
/// </summary>
public interface IDictionaryValidator
{
    /// <summary>Whether a dictionary is available for the 2-letter language code.</summary>
    bool IsAvailable(string lang);

    /// <summary>Whether <paramref name="word"/> (already lower-cased) is a real word in the language.</summary>
    bool IsValidWord(string word, string lang);
}

/// <summary>
/// The installed layouts and how keystrokes render through them — the platform binding for
/// enumeration + per-layout rendering (Win32 <c>GetKeyboardLayoutList</c> / <c>ToUnicodeEx</c> on
/// Windows; TIS / <c>UCKeyTranslate</c> on macOS).
/// </summary>
public interface ILayoutCatalog
{
    /// <summary>Installed layouts, in OS order.</summary>
    IReadOnlyList<Layout> InstalledLayouts();

    /// <summary>The id of the currently active layout.</summary>
    string CurrentLayoutId();

    /// <summary>
    /// Render the typed keys as <paramref name="layout"/> would produce them; null if the input
    /// can't be rendered in this layout (e.g. no layout data, or remote-desktop forwarded chars).
    /// </summary>
    string? Render(IReadOnlyList<TypedKey> keys, Layout layout);
}

/// <summary>The user's "always convert" override list (matched against the target/converted word).</summary>
public interface IAlwaysConvertList
{
    bool IsAlwaysConvert(string converted);
}

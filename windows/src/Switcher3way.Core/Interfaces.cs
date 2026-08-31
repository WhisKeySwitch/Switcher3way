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

    /// <summary>
    /// The language's letters, for generating the neighbours of a word. Hunspell dictionaries carry
    /// exactly this as their <c>TRY</c> line, ordered by frequency, because suggestion engines need
    /// the same thing. Empty means "unknown", and the near-miss check simply does not run — which is
    /// why this has a default: a validator that cannot answer should not have to.
    /// </summary>
    string Alphabet(string lang) => "";

    /// <summary>
    /// The language's vowels, for <see cref="WordShape.IsPlausible"/> (the gibberish-rescue path).
    /// Same fail-open convention as <see cref="Alphabet"/>: empty means "unknown", and the rescue
    /// simply does not run — a validator that cannot answer must not cause conversions.
    /// </summary>
    string Vowels(string lang) => "";

    /// <summary>
    /// Asked immediately before acting on this language's dictionary evidence: is the dictionary
    /// answering correctly <em>right now</em>? Periodic health checks leave a window in which a
    /// newly-lying dictionary would convert a name into keyboard mash and take the layout with it,
    /// and conversions are rare enough that the check is affordable here and nowhere else.
    /// Defaults to true: a validator that cannot verify itself is trusted exactly as before
    /// (Hunspell reads bundled files in-process and is deterministic, so on Windows it does).
    /// </summary>
    bool VerifyTrust(string lang) => true;
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

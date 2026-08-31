using System.Collections.Concurrent;
using Switcher3way.Core;
using WeCantSpell.Hunspell;

namespace Switcher3way.Dictionaries;

/// <summary>
/// <see cref="IDictionaryValidator"/> backed by bundled Hunspell dictionaries (managed
/// <c>WeCantSpell.Hunspell</c> — no native deps). Each 2-letter language loads
/// <c>&lt;dir&gt;/&lt;lang&gt;.dic</c> + <c>&lt;lang&gt;.aff</c> lazily and caches the result, so
/// detection stays offline and deterministic regardless of installed OS language packs.
/// </summary>
public sealed class HunspellDictionaryValidator : IDictionaryValidator
{
    private readonly string _directory;
    private readonly ConcurrentDictionary<string, WordList?> _cache = new();

    /// <param name="dictionaryDirectory">Folder holding <c>en.dic/en.aff</c>, <c>ru.dic/ru.aff</c>, …</param>
    public HunspellDictionaryValidator(string dictionaryDirectory) => _directory = dictionaryDirectory;

    /// <summary>Uses the <c>dict/</c> folder deployed next to the assembly (the bundled dictionaries).</summary>
    public HunspellDictionaryValidator() : this(Path.Combine(AppContext.BaseDirectory, "dict")) { }

    private static string Two(string lang) => lang.Length <= 2 ? lang : lang.Substring(0, 2);

    private WordList? Load(string lang) => _cache.GetOrAdd(Two(lang), l =>
    {
        var dic = Path.Combine(_directory, l + ".dic");
        var aff = Path.Combine(_directory, l + ".aff");
        if (!File.Exists(dic) || !File.Exists(aff)) return null;
        return WordList.CreateFromFiles(dic, aff);
    });

    public bool IsAvailable(string lang) => Load(lang) is not null;

    public bool IsValidWord(string word, string lang)
    {
        var list = Load(lang);
        return list is not null && list.Check(word);
    }

    private readonly ConcurrentDictionary<string, string> _alphabets = new();

    /// <summary>
    /// The language's letters, taken from the dictionary's own <c>TRY</c> line — the list Hunspell
    /// keeps, in frequency order, for building a misspelling's neighbours. Upper-case forms and the
    /// punctuation some dictionaries append are dropped: the near-miss check works on lower-cased
    /// letter cores, so trying <c>Ф</c> after <c>ф</c> only doubles the work.
    /// </summary>
    public string Alphabet(string lang) => _alphabets.GetOrAdd(Two(lang), l =>
    {
        var list = Load(l);
        var t = list?.Affix?.TryString;
        if (string.IsNullOrEmpty(t)) return "";
        var seen = new HashSet<char>();
        var sb = new System.Text.StringBuilder(t.Length);
        foreach (var c in t)
        {
            if (!char.IsLetter(c)) continue;
            var lower = char.ToLowerInvariant(c);
            if (seen.Add(lower)) sb.Append(lower);
        }
        return sb.ToString();
    });

    /// <summary>
    /// The language's vowels, for the gibberish-rescue shape check. Static knowledge, not derived:
    /// which letters are vowels is a fact about the language, and the three languages this app
    /// ships dictionaries for are known. Unlisted languages return "" — the rescue then never runs
    /// for them, the same fail-open convention as <see cref="Alphabet"/>.
    /// </summary>
    public string Vowels(string lang) => Two(lang) switch
    {
        "en" => "aeiouy",
        "uk" => "аеєиіїоуюя",
        "ru" => "аеёиоуыэюя",
        "bg" => "аеиоуъюя",          // ъ is a full vowel in Bulgarian, not a sign as in Russian
        // Serbian carries р, and this is linguistics rather than a workaround: syllabic R is a
        // syllable nucleus, which is why крв, прст, врх, трг, црн, брз, крст, врт and смрт — blood,
        // finger, top, square, black, fast, cross, garden, death — are ordinary words with no other
        // vowel in them. Without it the shape test calls correctly typed Serbian unpronounceable,
        // and the gibberish rescue may then convert it into another language.
        //
        // Measured against a rule that exempts such words from needing a vowel while still counting
        // р as a consonant for cluster length: both take real Serbian wrongly judged implausible from
        // 0.17% to 0.02%, and differ by half a percentage point on a gibberish control. Equivalent on
        // the evidence, so the simpler one wins. SerbianShapeTests keeps both scored.
        "sr" => "аеиоур",
        _ => "",
    };
}

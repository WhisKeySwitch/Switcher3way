using Switcher3way.Core;

namespace Switcher3way.Core.Tests;

/// <summary>Dictionary fake: seeded available languages and valid words (lower-cased) per language.</summary>
internal sealed class FakeDict : IDictionaryValidator
{
    private readonly HashSet<string> _available;
    private readonly Dictionary<string, HashSet<string>> _words;

    /// <summary>Letters per language, for <see cref="TypoGuard.NearMiss"/>. Empty by default —
    /// a test only pays for the near-miss check when it seeds one.</summary>
    public Dictionary<string, string> Alphabets { get; } = new();

    /// <summary>Vowels per language, for the gibberish rescue's <see cref="WordShape"/> check.
    /// Empty by default, which switches the rescue off — existing tests reason about the
    /// dictionary path undisturbed.</summary>
    public Dictionary<string, string> VowelSets { get; } = new();

    public FakeDict(IEnumerable<string> available, Dictionary<string, HashSet<string>> words)
    {
        _available = new HashSet<string>(available);
        _words = words;
    }

    public bool IsAvailable(string lang) => _available.Contains(lang);

    public bool IsValidWord(string word, string lang) =>
        _words.TryGetValue(lang, out var set) && set.Contains(word);

    public string Alphabet(string lang) => Alphabets.TryGetValue(lang, out var a) ? a : "";

    public string Vowels(string lang) => VowelSets.TryGetValue(lang, out var v) ? v : "";
}

/// <summary>
/// Layout catalog fake: a fixed layout list, a current id, and a per-layout render map. The keys
/// argument is ignored — a test seeds exactly what each layout should render for its single word.
/// </summary>
internal sealed class FakeCatalog : ILayoutCatalog
{
    private readonly List<Layout> _layouts;
    private readonly string _current;
    private readonly Dictionary<string, string?> _renders;

    public FakeCatalog(List<Layout> layouts, string current, Dictionary<string, string?> renders)
    {
        _layouts = layouts;
        _current = current;
        _renders = renders;
    }

    public IReadOnlyList<Layout> InstalledLayouts() => _layouts;
    public string CurrentLayoutId() => _current;

    public string? Render(IReadOnlyList<TypedKey> keys, Layout layout) =>
        _renders.TryGetValue(layout.Id, out var s) ? s : null;
}

internal sealed class FakeAlways : IAlwaysConvertList
{
    private readonly HashSet<string> _set;
    public FakeAlways(params string[] words) =>
        _set = new HashSet<string>(words.Select(w => w.ToLowerInvariant()));
    public bool IsAlwaysConvert(string converted) => _set.Contains(converted.ToLowerInvariant());
}

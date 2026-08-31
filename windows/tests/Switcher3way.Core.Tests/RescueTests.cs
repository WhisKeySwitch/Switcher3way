using Switcher3way.Core;
using Switcher3way.Dictionaries;
using Xunit;
using Xunit.Abstractions;

namespace Switcher3way.Core.Tests;

/// <summary>
/// The QWERTY ↔ ЙЦУКЕН correspondence for the letters the rescue fixture uses — how one token
/// looks through each of the three layouts. Mirrors the macOS test fixture's key table.
/// </summary>
internal static class TriRender
{
    private static readonly (char En, char Uk, char Ru)[] Rows =
    {
        ('a', 'ф', 'ф'), ('s', 'і', 'ы'), ('d', 'в', 'в'), ('f', 'а', 'а'),
        ('h', 'р', 'р'), ('g', 'п', 'п'), ('z', 'я', 'я'), ('x', 'ч', 'ч'),
        ('c', 'с', 'с'), ('v', 'м', 'м'), ('b', 'и', 'и'), ('q', 'й', 'й'),
        ('w', 'ц', 'ц'), ('e', 'у', 'у'), ('r', 'к', 'к'), ('y', 'н', 'н'),
        ('t', 'е', 'е'), ('o', 'щ', 'щ'), ('u', 'г', 'г'), ('i', 'ш', 'ш'),
        ('p', 'з', 'з'), ('l', 'д', 'д'), ('j', 'о', 'о'), ('k', 'л', 'л'),
        ('n', 'т', 'т'), ('m', 'ь', 'ь'), ('\'', 'є', 'э'), (';', 'ж', 'ж'),
        (',', 'б', 'б'), ('.', 'ю', 'ю'), (']', 'ї', 'ъ'), ('[', 'х', 'х'),
    };

    /// <summary>A token typed as Latin keystrokes, rendered in each layout's script.</summary>
    public static Dictionary<string, string?> FromLatin(string latin) => new()
    {
        ["en"] = latin,
        ["uk"] = Map(latin, r => r.En, r => r.Uk),
        ["ru"] = Map(latin, r => r.En, r => r.Ru),
    };

    /// <summary>A token typed as Ukrainian keystrokes, rendered in each layout's script.</summary>
    public static Dictionary<string, string?> FromUkrainian(string uk) => new()
    {
        ["uk"] = uk,
        ["en"] = Map(uk, r => r.Uk, r => r.En),
        ["ru"] = Map(Map(uk, r => r.Uk, r => r.En), r => r.En, r => r.Ru),
    };

    private static string Map(string word, Func<(char En, char Uk, char Ru), char> from,
                              Func<(char En, char Uk, char Ru), char> to)
    {
        var outChars = new char[word.Length];
        for (var i = 0; i < word.Length; i++)
        {
            var lower = char.ToLowerInvariant(word[i]);
            var row = Array.FindIndex(Rows, r => from(r) == lower);
            if (row < 0) throw new InvalidOperationException($"'{word[i]}' is not in the key table");
            var mapped = to(Rows[row]);
            outChars[i] = char.IsUpper(word[i]) ? char.ToUpperInvariant(mapped) : mapped;
        }
        return new string(outChars);
    }
}

/// <summary>
/// The gibberish rescue on deterministic fakes: every branch of <see cref="NWayResolver"/>'s
/// rescue and its interaction with the gates around it. Mirrors the macOS <c>RescueTests</c>.
/// </summary>
public class RescueTests
{
    private static readonly List<Layout> Layouts = new() { new("en", "en"), new("uk", "uk"), new("ru", "ru") };
    private static readonly TypedKey[] Key = { new(1, false, false) };

    private static NWayResolver Resolver(string current, Dictionary<string, string?> renders,
                                         bool vowelled = true,
                                         Dictionary<string, HashSet<string>>? words = null,
                                         string enAlphabet = "")
    {
        var dict = new FakeDict(new[] { "en", "uk", "ru" },
                                words ?? new() { ["en"] = new(), ["uk"] = new(), ["ru"] = new() });
        if (vowelled)
        {
            dict.VowelSets["en"] = "aeiouy";
            dict.VowelSets["uk"] = "аеєиіїоуюя";
            dict.VowelSets["ru"] = "аеёиоуыэюя";
        }
        if (enAlphabet.Length > 0) dict.Alphabets["en"] = enAlphabet;
        return new NWayResolver(new FakeCatalog(Layouts, current, renders), dict, new FakeAlways());
    }

    [Fact]
    public void LatinGibberish_withCyrillicShape_isAmbiguousRescue()
    {
        var outcome = Resolver("en", TriRender.FromLatin("fgrf")).Evaluate(Key, capsLock: false);
        var amb = Assert.IsType<Outcome.Ambiguous>(outcome);
        Assert.Equal("fgrf", amb.Original);
        Assert.Equal(new[] { "ru", "uk" }, amb.Winners.Select(w => w.Lang).OrderBy(l => l));
        Assert.Equal("апка", amb.Winners.First(w => w.Lang == "uk").Converted);
    }

    [Fact]
    public void CyrillicGibberish_withUniqueEnglishShape_isRescued()
    {
        var outcome = Resolver("uk", TriRender.FromUkrainian("лншм")).Evaluate(Key, capsLock: false);
        var r = Assert.IsType<Outcome.Rescued>(outcome);
        Assert.Equal("en", r.Decision.TargetLayoutId);
        Assert.Equal("kyiv", r.Decision.Converted);
        Assert.Equal("лншм", r.Decision.Original);
    }

    [Fact]
    public void PlausibleInTypedLanguage_keeps()
    {
        var outcome = Resolver("en", TriRender.FromLatin("kyiv")).Evaluate(Key, capsLock: false);
        var keep = Assert.IsType<Outcome.Keep>(outcome);
        Assert.Equal(KeepReason.NotAWordAnywhere, keep.Reason);
    }

    [Fact]
    public void GibberishEverywhere_keeps()
    {
        var outcome = Resolver("en", TriRender.FromLatin("gkml")).Evaluate(Key, capsLock: false);
        Assert.IsType<Outcome.Keep>(outcome);
    }

    [Fact]
    public void AllCaps_isVetoedBeforeRescue()
    {
        var outcome = Resolver("en", TriRender.FromLatin("FGRF")).Evaluate(Key, capsLock: false);
        Assert.IsType<Outcome.Keep>(outcome);
    }

    [Fact]
    public void BelowFloor_keeps()
    {
        var outcome = Resolver("en", TriRender.FromLatin("fgf")).Evaluate(Key, capsLock: false);
        Assert.IsType<Outcome.Keep>(outcome);
    }

    [Fact]
    public void NoVowelSets_disablesRescue()
    {
        var outcome = Resolver("en", TriRender.FromLatin("fgrf"), vowelled: false)
            .Evaluate(Key, capsLock: false);
        Assert.IsType<Outcome.Keep>(outcome);
    }

    [Fact]
    public void NearMissOfTypedLanguage_vetoesRescue()
    {
        var outcome = Resolver("en", TriRender.FromLatin("ftyf"),
                               words: new() { ["en"] = new() { "ftya" }, ["uk"] = new(), ["ru"] = new() },
                               enAlphabet: "abcdefghijklmnopqrstuvwxyz")
            .Evaluate(Key, capsLock: false);
        var keep = Assert.IsType<Outcome.Keep>(outcome);
        Assert.Equal(KeepReason.LooksLikeATypo, keep.Reason);
    }

    [Fact]
    public void ManualPlan_promotesRescuedCandidate()
    {
        var plan = Resolver("uk", TriRender.FromUkrainian("лншм"))
            .ManualPlan(Key, capsLock: false, preferredAmbiguityLang: "uk");
        Assert.NotNull(plan);
        Assert.Equal("kyiv", plan!.Candidates[0].Converted);
    }
}

/// <summary>
/// The rescue measured against the REAL bundled dictionaries — the fixture and contracts mirror
/// the macOS <c>RescueQualityTests</c>: the keep side is a hard zero-conversions gate, the rescue
/// side is a reported recall with a loose floor. The printout is the number design.md records.
/// </summary>
public class RescueQualityTests
{
    private static readonly HunspellDictionaryValidator Real = new();
    private static readonly List<Layout> Layouts = new() { new("en", "en"), new("uk", "uk"), new("ru", "ru") };
    private static readonly TypedKey[] Key = { new(1, false, false) };
    private readonly ITestOutputHelper _output;

    public RescueQualityTests(ITestOutputHelper output) => _output = output;

    private static NWayResolver Resolver(string current, Dictionary<string, string?> renders) =>
        new(new FakeCatalog(Layouts, current, renders), Real, new FakeAlways());

    private static readonly string[] KeepEnglish =
    {
        "kyiv", "lviv",
        "ctrl", "html", "http", "https", "smtp", "grpc",
        "json", "yaml", "sudo", "grep", "bash", "linux", "github", "kubectl", "sqlite", "nginx",
        "peopleops", "snipeit",
        "emergancy", "recieve",
        "asap", "lorem", "ipsum",
    };

    private static readonly string[] KeepUkrainian = { "імхо", "лол", "хзхз" };

    private static readonly (string Typed, string ExpectedUk)[] RescueLatinToCyrillic =
    {
        ("fgrf", "апка"),
        ("fqls", "айді"),
        ("ntyfyne", "тенанту"),
        ("xtryenb", "чекнути"),
        ("rfibh", "кашир"),
    };

    private static readonly (string TypedUk, string ExpectedEn)[] RescueCyrillicToLatin =
    {
        ("лншм", "kyiv"),
        ("дштгч", "linux"),
        // Field miss 2026-08-31: one vowel + a 4-consonant TAIL read as "plausible ru" until the
        // trailing-cluster cap was added.
        ("шкудфтв", "ireland"),
    };

    private const double MinRescueRecall = 0.6;

    private static bool IsConverted(Outcome o) => o is Outcome.Rescued or Outcome.Ambiguous;

    [Fact]
    public void KeepSideEnglish_isNeverConverted()
    {
        foreach (var token in KeepEnglish)
        {
            var outcome = Resolver("en", TriRender.FromLatin(token)).Evaluate(Key, capsLock: false);
            Assert.False(IsConverted(outcome),
                         $"rescue-quality: '{token}' (typed in its own layout) got {outcome}");
        }
    }

    [Fact]
    public void KeepSideUkrainian_isNeverConverted()
    {
        foreach (var token in KeepUkrainian)
        {
            var outcome = Resolver("uk", TriRender.FromUkrainian(token)).Evaluate(Key, capsLock: false);
            Assert.False(IsConverted(outcome),
                         $"rescue-quality: '{token}' (typed in its own layout) got {outcome}");
        }
    }

    [Fact]
    public void RescueRecall_latinToCyrillic()
    {
        var hits = 0;
        var misses = new List<string>();
        foreach (var (typed, expectedUk) in RescueLatinToCyrillic)
        {
            var outcome = Resolver("en", TriRender.FromLatin(typed)).Evaluate(Key, capsLock: false);
            var hit = outcome switch
            {
                Outcome.Rescued r => r.Decision.Converted == expectedUk,
                Outcome.Ambiguous a => a.Winners.Any(w => w.Lang == "uk" && w.Converted == expectedUk),
                Outcome.Convert c => c.Decision.Converted == expectedUk, // dictionary got there first
                _ => false,
            };
            if (hit) hits++; else misses.Add($"{typed}→{expectedUk} got {outcome}");
        }
        _output.WriteLine($"rescue-quality: latin→cyrillic recall {(double)hits / RescueLatinToCyrillic.Length:F2} " +
                          $"({hits}/{RescueLatinToCyrillic.Length})" +
                          (misses.Count == 0 ? "" : $" — missed: {string.Join("; ", misses)}"));
        Assert.True((double)hits / RescueLatinToCyrillic.Length >= MinRescueRecall);
    }

    [Fact]
    public void RescueRecall_cyrillicToLatin()
    {
        var hits = 0;
        var misses = new List<string>();
        foreach (var (typedUk, expectedEn) in RescueCyrillicToLatin)
        {
            var outcome = Resolver("uk", TriRender.FromUkrainian(typedUk)).Evaluate(Key, capsLock: false);
            var hit = outcome switch
            {
                Outcome.Rescued r => r.Decision.Converted == expectedEn,
                Outcome.Convert c => c.Decision.Converted == expectedEn,
                _ => false,
            };
            if (hit) hits++; else misses.Add($"{typedUk}→{expectedEn} got {outcome}");
        }
        _output.WriteLine($"rescue-quality: cyrillic→latin recall {(double)hits / RescueCyrillicToLatin.Length:F2} " +
                          $"({hits}/{RescueCyrillicToLatin.Length})" +
                          (misses.Count == 0 ? "" : $" — missed: {string.Join("; ", misses)}"));
        Assert.True((double)hits / RescueCyrillicToLatin.Length >= MinRescueRecall);
    }
}

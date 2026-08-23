using System.Text;
using Switcher3way.Core;
using Switcher3way.Dictionaries;
using Xunit;
using Xunit.Abstractions;

namespace Switcher3way.Core.Tests;

/// <summary>
/// The precision property the app lives or dies by, measured rather than asserted in the abstract:
/// **a typo must not be mistaken for wrong-layout typing**.
///
/// A user reported abandoning the app because "every typo switches me to EN" — she writes Ukrainian,
/// mistypes a word, and the app converts the mistyped word to Latin and switches the layout, so the
/// rest of the paragraph lands in English until she notices. The mechanism is structural: a typo makes
/// the current-language dictionary check fail, and the resolver then accepts *any* other language whose
/// rendering happens to be a real word. English, with a large dictionary full of short words, wins often.
///
/// These tests build the real ЙЦУКЕН↔QWERTY mapping and run real Ukrainian words, and single-edit typos
/// of them, through the resolver with the real dictionaries.
/// </summary>
public class TypoFalsePositiveTests
{
    private readonly ITestOutputHelper _out;
    public TypoFalsePositiveTests(ITestOutputHelper output) => _out = output;

    private static readonly HunspellDictionaryValidator Real = new();

    // Key → character, by layout. The key is the QWERTY letter, which is also the en rendering.
    private const string Keys = "qwertyuiop[]asdfghjkl;'zxcvbnm,.";
    private const string Uk   = "йцукенгшщзхїфівапролджєячсмитьбю";
    private const string Ru   = "йцукенгшщзхъфывапролджэячсмитьбю";

    private static readonly Dictionary<char, char> UkToKey = BuildReverse(Uk);
    private static Dictionary<char, char> BuildReverse(string layout)
    {
        var m = new Dictionary<char, char>();
        for (int i = 0; i < Keys.Length; i++) m[layout[i]] = Keys[i];
        return m;
    }

    /// <summary>Typed keys for a Ukrainian word, or null if it uses a key we do not model.</summary>
    private static List<TypedKey>? KeysFor(string ukWord)
    {
        var keys = new List<TypedKey>();
        foreach (var ch in ukWord)
        {
            if (!UkToKey.TryGetValue(ch, out var k)) return null;
            keys.Add(new TypedKey(k, Shift: false, Caps: false));
        }
        return keys;
    }

    private static string RenderIn(IReadOnlyList<TypedKey> keys, string layout)
    {
        var sb = new StringBuilder();
        foreach (var k in keys)
        {
            int i = Keys.IndexOf((char)k.KeyCode);
            sb.Append(layout switch { "uk" => Uk[i], "ru" => Ru[i], _ => Keys[i] });
        }
        return sb.ToString();
    }

    private sealed class RealisticCatalog : ILayoutCatalog
    {
        public IReadOnlyList<Layout> InstalledLayouts() =>
            new List<Layout> { new("en", "en"), new("ru", "ru"), new("uk", "uk") };
        public string CurrentLayoutId() => "uk";          // she is typing Ukrainian
        public string? Render(IReadOnlyList<TypedKey> keys, Layout layout) => RenderIn(keys, layout.Id);
        public IReadOnlyDictionary<char, TypedKey> ReverseMap(Layout layout) => new Dictionary<char, TypedKey>();
    }

    private static NWayResolver Resolver() =>
        new(new RealisticCatalog(), Real, new FakeAlways());

    /// <summary>Real Ukrainian words, and one-edit typos of them a person would plausibly make.</summary>
    private static IEnumerable<(string Word, string Typo, string Kind)> Typos()
    {
        // Everyday words; the typos are a dropped letter, a doubled letter, a transposition, or a
        // neighbouring-key slip — the four things fingers actually do.
        var words = new[]
        {
            "привіт", "дякую", "будинок", "робота", "місто", "дитина", "книга", "щастя",
            "погода", "сонце", "вулиця", "друзі", "музика", "ранок", "вечір", "тиждень",
            "поїзд", "квиток", "гроші", "хвилина", "година", "тепло", "холодно", "смачно",
            "потрібно", "можливо", "звичайно", "напевно", "разом", "окремо", "швидко", "повільно",
        };
        foreach (var w in words)
        {
            if (w.Length > 2) yield return (w, w.Remove(1, 1), "dropped letter");
            if (w.Length > 2) yield return (w, w.Insert(1, w[1].ToString()), "doubled letter");
            if (w.Length > 3) yield return (w, string.Concat(w[0], w[2], w[1], w[3..]), "transposed");
            yield return (w, w[..^1] + (w[^1] == 'а' ? 'о' : 'а'), "wrong last letter");
        }
    }

    /// <summary>
    /// Short words are where the danger is. The layout mapping is effectively a random permutation, and
    /// a large fraction of two- and three-letter Latin strings are English words — so a short Ukrainian
    /// word that is mistyped, or simply missing from the dictionary, has a real chance of rendering as
    /// valid English and being "corrected" into it.
    /// </summary>
    private static IEnumerable<(string Word, string Typo, string Kind)> ShortTypos()
    {
        var words = new[]
        {
            "не", "на", "за", "до", "то", "як", "що", "це", "ми", "ви", "він", "так", "але",
            "чи", "бо", "від", "під", "над", "про", "три", "два", "рік", "має", "був", "усі",
            "дім", "рух", "сік", "ніс", "лід", "мед", "сад", "рис", "кіт", "сіль", "день",
        };
        foreach (var w in words)
        {
            foreach (var repl in new[] { 'а', 'о', 'и', 'е', 'і' })
            {
                if (w[^1] != repl) yield return (w, w[..^1] + repl, $"last letter → {repl}");
                if (w.Length > 1 && w[0] != repl) yield return (w, repl + w[1..], $"first letter → {repl}");
            }
            if (w.Length > 2) yield return (w, w.Remove(1, 1), "dropped letter");
            yield return (w, w + w[^1], "doubled last letter");
        }
    }

    [Fact]
    public void ShortTypos_areNotMistakenForWrongLayout()
    {
        var resolver = Resolver();
        int total = 0, converted = 0;
        var examples = new List<string>();
        foreach (var (word, typo, kind) in ShortTypos())
        {
            var keys = KeysFor(typo);
            if (keys is null) continue;
            total++;
            if (resolver.Evaluate(keys, capsLock: false) is Outcome.Convert c)
            {
                converted++;
                if (examples.Count < 30)
                    examples.Add($"\"{word}\" mistyped as \"{typo}\" ({kind}) → became \"{c.Decision.Converted}\" [{c.Decision.TargetLayoutId}]");
            }
        }
        _out.WriteLine($"SHORT typos: {total}, wrongly converted: {converted} ({100.0 * converted / total:F1}%)");
        foreach (var e in examples) _out.WriteLine("  " + e);
        Assert.True(converted == 0, $"{converted}/{total} short typos were converted");
    }

    [Fact]
    public void CorrectlyTypedUkrainian_isLeftAlone()
    {
        var resolver = Resolver();
        var wrong = new List<string>();
        foreach (var (word, _, _) in Typos().DistinctBy(t => t.Word))
        {
            var keys = KeysFor(word);
            if (keys is null) continue;
            if (resolver.Evaluate(keys, capsLock: false) is not Outcome.Keep) wrong.Add(word);
        }
        _out.WriteLine($"correctly typed words converted anyway: {wrong.Count} — {string.Join(", ", wrong)}");
        Assert.Empty(wrong);
    }

    [Fact]
    public void Typos_areNotMistakenForWrongLayout()
    {
        var resolver = Resolver();
        int total = 0, converted = 0;
        var examples = new List<string>();
        foreach (var (word, typo, kind) in Typos())
        {
            var keys = KeysFor(typo);
            if (keys is null) continue;
            total++;
            if (resolver.Evaluate(keys, capsLock: false) is Outcome.Convert c)
            {
                converted++;
                if (examples.Count < 25)
                    examples.Add($"{word} → mistyped \"{typo}\" ({kind}) → became \"{c.Decision.Converted}\" [{c.Decision.TargetLayoutId}]");
            }
        }
        _out.WriteLine($"typos: {total}, wrongly converted: {converted} ({100.0 * converted / total:F1}%)");
        foreach (var e in examples) _out.WriteLine("  " + e);
        Assert.True(converted == 0, $"{converted}/{total} typos were converted; a typo is not a layout mistake");
    }
}

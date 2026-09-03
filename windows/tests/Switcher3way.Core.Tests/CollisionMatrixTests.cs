using System.Text;
using Switcher3way.Core;
using Switcher3way.Dictionaries;
using Xunit;
using Xunit.Abstractions;

namespace Switcher3way.Core.Tests;

/// <summary>
/// Prices a candidate language before any of it is built, the same way the typo guard was priced.
///
/// Adding a Cyrillic language is not "one more dictionary". Detection works by rendering the same
/// keystrokes through every installed layout and asking which language claims the result, so a
/// language that shares both an alphabet and a keyboard layout with one already supported produces
/// renderings that are *character-for-character identical*. Whenever both dictionaries then accept
/// the word, the resolver has no way to choose: it reports an ambiguity, and the user gets whichever
/// language their preference names — or nothing.
///
/// So the number that decides whether a language can be added is not its speaker count. It is how
/// often it collides with the languages already there. This measures exactly that, against the real
/// dictionaries, using the app's own validator.
///
/// Skipped unless the candidate dictionaries are staged, so it never breaks a normal test run.
/// </summary>
public class CollisionMatrixTests
{
    private readonly ITestOutputHelper _out;
    public CollisionMatrixTests(ITestOutputHelper o) => _out = o;

    /// <summary>Where the candidate dictionaries are staged for the experiment.</summary>
    private static readonly string Dir =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                     "Temp", "dictprobe");

    /// <summary>Base forms from a Hunspell .dic — the word before any affix flags.</summary>
    private static List<string> Words(string lang, int max)
    {
        var path = Path.Combine(Dir, lang + ".dic");
        var res = new List<string>(max);
        var rnd = new Random(20260831);          // fixed, so the matrix is reproducible
        foreach (var raw in File.ReadLines(path).Skip(1))
        {
            var w = raw.Split('/')[0].Split('\t')[0].Trim().ToLowerInvariant();
            if (w.Length < 3 || !w.All(char.IsLetter)) continue;
            if (res.Count < max) res.Add(w);
            else if (rnd.Next(res.Count) is int i && i < max) res[i] = w;   // reservoir
        }
        return res;
    }

    [Fact]
    public void Cross_language_collision_matrix()
    {
        if (!Directory.Exists(Dir) || !File.Exists(Path.Combine(Dir, "be.dic")))
        {
            _out.WriteLine($"candidate dictionaries not staged in {Dir} — skipping");
            return;
        }

        var dict = new HunspellDictionaryValidator(Dir);
        var langs = new[] { "en", "ru", "uk", "be", "bg", "sr" };
        const int sample = 20000;

        var words = langs.ToDictionary(l => l, l => Words(l, sample));
        _out.WriteLine("sampled base forms: " +
                       string.Join("  ", langs.Select(l => $"{l}={words[l].Count}")));
        _out.WriteLine("");
        _out.WriteLine("Share of language A's own words that language B also accepts.");
        _out.WriteLine("For languages sharing an alphabet AND a keyboard layout, this IS the");
        _out.WriteLine("ambiguity rate: the rendering is identical, so both claim the same word.");
        _out.WriteLine("");
        _out.WriteLine("   A/B   " + string.Join("  ", langs.Select(l => l.PadLeft(6))));

        foreach (var a in langs)
        {
            var row = new StringBuilder($"   {a,-6}");
            foreach (var b in langs)
            {
                if (a == b) { row.Append("      —"); continue; }
                var hits = words[a].Count(w => dict.IsValidWord(w, b));
                row.Append($"{100.0 * hits / words[a].Count,6:F1}%");
            }
            _out.WriteLine(row.ToString());
        }
    }

    /// <summary>
    /// The question that decides whether a new language may ship at all: does adding it cost the
    /// users who are already here?
    ///
    /// Every extra installed language is another chance for a fumbled word to be a real word
    /// somewhere, and a false conversion moves the layout as well as the text. This runs the same
    /// Ukrainian and English typo corpora the precision work uses, once with today's three languages
    /// and once with the candidates added, and compares. Anything above zero on the second run is a
    /// cost paid by people who do not speak the language being added.
    ///
    /// The candidates are rendered through ЙЦУКЕН here, which they do NOT use — Bulgarian is BDS and
    /// Serbian is QWERTZ-aligned. That is deliberate: it is the worst case, in which their renderings
    /// coincide with Russian and Ukrainian instead of diverging. Real layouts can only do better.
    /// </summary>
    [Fact]
    public void Adding_languages_must_not_cost_the_users_already_here()
    {
        if (!Directory.Exists(Dir) || !File.Exists(Path.Combine(Dir, "bg.dic")))
        {
            _out.WriteLine($"candidate dictionaries not staged in {Dir} — skipping");
            return;
        }
        var dict = new HunspellDictionaryValidator(Dir);

        foreach (var (corpus, own) in new[] { (PrecisionRecallCorpus.Uk, "uk"), (PrecisionRecallCorpus.En, "en") })
            foreach (var installed in new[] { new[] { "en", "uk", "ru" },
                                              new[] { "en", "uk", "ru", "bg", "sr" } })
            {
                var r = new NWayResolver(new WideCatalog(own, installed), dict, new NoAlways2());
                int total = 0, converted = 0;
                var examples = new List<string>();
                foreach (var w in Words(corpus))
                    foreach (var typo in TyposOf(w))
                    {
                        var keys = KeysFor(typo);
                        if (keys is null || typo.Length < 2) continue;
                        total++;
                        if (r.Evaluate(keys, capsLock: false) is Outcome.Convert c)
                        {
                            converted++;
                            if (examples.Count < 5)
                                examples.Add($"{typo}->{c.Decision.Converted}[{c.Decision.TargetLayoutId}]");
                        }
                    }
                _out.WriteLine($"  {own} typos, layouts {string.Join("+", installed),-20} "
                               + $"{converted,3}/{total} converted ({100.0 * converted / total:F2}%)"
                               + (examples.Count > 0 ? "   " + string.Join(" ", examples) : ""));
            }
    }

    // ---- self-contained fakes, so this experiment does not entangle the precision suite

    private const string Keys = "qwertyuiop[]asdfghjkl;'zxcvbnm,.";
    private const string UkRow = "йцукенгшщзхїфівапролджєячсмитьбю";
    private const string RuRow = "йцукенгшщзхъфывапролджэячсмитьбю";

    private static readonly Dictionary<char, char> UkToKey =
        Enumerable.Range(0, Keys.Length).ToDictionary(i => UkRow[i], i => Keys[i]);

    private static IEnumerable<string> Words(string corpus) =>
        corpus.Split(new[] { ' ', '\n', '\r', '\t', ',', '.', '!', '?', ';', ':' },
                     StringSplitOptions.RemoveEmptyEntries)
              .Select(w => w.Trim().ToLowerInvariant()).Where(w => w.Length >= 2).Distinct();

    private static List<TypedKey>? KeysFor(string word)
    {
        var keys = new List<TypedKey>();
        foreach (var ch in word)
        {
            char k;
            if (UkToKey.TryGetValue(ch, out var mapped)) k = mapped;
            else if (Keys.Contains(ch)) k = ch;
            else return null;
            keys.Add(new TypedKey(k, Shift: false, Caps: false));
        }
        return keys;
    }

    private static IEnumerable<string> TyposOf(string w)
    {
        for (int i = 0; i < w.Length; i++) yield return w.Remove(i, 1);
        for (int i = 0; i < w.Length; i++) yield return w.Insert(i, w[i].ToString());
        for (int i = 0; i + 1 < w.Length; i++)
        {
            var a = w.ToCharArray(); (a[i], a[i + 1]) = (a[i + 1], a[i]);
            yield return new string(a);
        }
    }

    /// <summary>Every Cyrillic candidate rendered through ЙЦУКЕН — the worst case, see the test.</summary>
    private sealed class WideCatalog : ILayoutCatalog
    {
        private readonly string _current; private readonly string[] _ids;
        public WideCatalog(string current, string[] ids) { _current = current; _ids = ids; }
        public IReadOnlyList<Layout> InstalledLayouts() => _ids.Select(i => new Layout(i, i)).ToList();
        public string? CurrentLayoutId() => _current;
        public string? Render(IReadOnlyList<TypedKey> keys, Layout layout)
        {
            var sb = new StringBuilder();
            foreach (var k in keys)
            {
                int i = Keys.IndexOf((char)k.KeyCode);
                if (i < 0) return null;
                sb.Append(layout.Id == "en" ? Keys[i] : layout.Id == "ru" ? RuRow[i] : UkRow[i]);
            }
            return sb.ToString();
        }
    }

    private sealed class NoAlways2 : IAlwaysConvertList { public bool IsAlwaysConvert(string w) => false; }
}

using System.Text;
using Switcher3way.Core;
using Switcher3way.Dictionaries;
using Xunit;
using Xunit.Abstractions;

namespace Switcher3way.Core.Tests;

/// <summary>
/// The two numbers that decide whether the app is worth running, measured against natural text
/// rather than argued about:
///
///   RECALL    — you forgot to switch layout and typed a whole word blind. Does it get fixed?
///   PRECISION — you are typing in your own language and fumble a key. Is it left alone?
///
/// A user abandoned the app over the second one: "every typo makes it switch to EN from UK", leaving
/// a long Ukrainian text with English garbage scattered through it. Recall is what the app is for,
/// so any cure for precision has to be priced in recall rather than assumed free.
/// </summary>
public class PrecisionRecallTests
{
    private readonly ITestOutputHelper _out;
    public PrecisionRecallTests(ITestOutputHelper o) => _out = o;

    private static readonly HunspellDictionaryValidator Real = new();

    private const string Keys = "qwertyuiop[]asdfghjkl;'zxcvbnm,.";
    private const string Uk = "йцукенгшщзхїфівапролджєячсмитьбю";
    private const string Ru = "йцукенгшщзхъфывапролджэячсмитьбю";

    /// <summary>Natural Ukrainian prose — the words a person actually writes, at their real length mix.</summary>
    private const string UkCorpus = @"
        Сьогодні я хочу написати кілька речень українською мовою, щоб перевірити, як програма
        поводиться зі звичайним текстом. Коли я друкую швидко, то часто помиляюся, і це нормально,
        адже ніхто не пише без помилок. Важливо, щоб програма не намагалася виправити те, що
        виправляти не треба. Наприклад, якщо я пропущу одну літеру в слові, то це просто описка,
        а не інша розкладка клавіатури. Ми з колегами обговорювали це питання і дійшли висновку,
        що краще залишити слово без змін, ніж перетворити його на щось незрозуміле. Я дуже люблю
        свою роботу, але іноді вона забирає надто багато часу. Треба знайти баланс між роботою
        та відпочинком. Завтра буде новий день, і все вийде добре.";

    private const string EnCorpus = @"
        I want to write a few sentences in English so the app can be checked against ordinary text
        as well. When I type quickly I make mistakes, and that is fine, because nobody writes
        without them. What matters is that the tool does not try to fix what is not broken. If I
        drop a letter from a word, that is a typo and not a different keyboard layout. We talked
        about this with my colleagues and agreed it is better to leave a word alone than to turn
        it into something nobody can read. I like my job a lot, but it takes too much time. There
        has to be a balance between work and rest, and tomorrow will be a better day.";

    private static IEnumerable<string> Words(string corpus) =>
        corpus.Split(new[] { ' ', '\n', '\r', '\t', ',', '.', '!', '?', ';', ':' },
                     StringSplitOptions.RemoveEmptyEntries)
              .Select(w => w.Trim().ToLowerInvariant())
              .Where(w => w.Length >= 2)
              .Distinct();

    private static Dictionary<char, char> Reverse(string layout)
    {
        var m = new Dictionary<char, char>();
        for (int i = 0; i < Keys.Length; i++) m[layout[i]] = Keys[i];
        return m;
    }
    private static readonly Dictionary<char, char> UkToKey = Reverse(Uk);

    /// <summary>Keys for a word: Ukrainian goes through the ЙЦУКЕН map, Latin is its own key.</summary>
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

    private sealed class Catalog : ILayoutCatalog
    {
        private readonly string _current;
        public Catalog(string current) => _current = current;
        public IReadOnlyList<Layout> InstalledLayouts() => new[]
        {
            new Layout("en", "en"),
            new Layout("uk", "uk"),
            new Layout("ru", "ru"),
        };
        public string? CurrentLayoutId() => _current;
        public string? Render(IReadOnlyList<TypedKey> keys, Layout layout)
        {
            var sb = new StringBuilder();
            foreach (var k in keys)
            {
                int i = Keys.IndexOf((char)k.KeyCode);
                if (i < 0) return null;
                sb.Append(layout.Id switch { "uk" => Uk[i], "ru" => Ru[i], _ => Keys[i] });
            }
            return sb.ToString();
        }
    }

    private sealed class NoAlways : IAlwaysConvertList { public bool IsAlwaysConvert(string w) => false; }
    private static NWayResolver Resolver(string current) => new(new Catalog(current), Real, new NoAlways());

    /// <summary>Single-edit typos: the fumbles a fast typist actually makes.</summary>
    private static IEnumerable<(string Typo, string Kind)> TyposOf(string w)
    {
        for (int i = 0; i < w.Length; i++) yield return (w.Remove(i, 1), "dropped");
        for (int i = 0; i < w.Length; i++) yield return (w.Insert(i, w[i].ToString()), "doubled");
        for (int i = 0; i + 1 < w.Length; i++)
        {
            var a = w.ToCharArray();
            (a[i], a[i + 1]) = (a[i + 1], a[i]);
            yield return (new string(a), "transposed");
        }
    }

    /// <summary>
    /// How often the near-miss test cries wolf, by word length. It asks whether ANY of the word's
    /// one-edit neighbours is real, and the number of neighbours grows with the alphabet — about 300
    /// of them for a four-letter Ukrainian word. Against a language with dense short-word coverage,
    /// enough of those land on something real that the test stops discriminating. This finds where
    /// it starts being worth listening to.
    /// </summary>
    [Fact]
    public void Near_miss_false_alarm_rate_by_length()
    {
        // Genuine wrong-layout typing: real words of one language rendered through the other. Nothing
        // here is a typo, so every fire is a false alarm.
        foreach (var (corpus, wrongLayout) in new[] { (PrecisionRecallCorpus.Uk, "en"), (PrecisionRecallCorpus.En, "uk") })
        {
            var r = Resolver(wrongLayout);
            var byLen = new SortedDictionary<int, (int total, int fired)>();
            foreach (var w in Words(corpus))
            {
                var keys = KeysFor(w);
                if (keys is null) continue;
                var shown = SoftGates.LetterCore(r.RenderCurrent(keys)!).ToLowerInvariant();
                if (shown.Length < 2) continue;
                var e = byLen.GetValueOrDefault(shown.Length);
                byLen[shown.Length] = (e.total + 1,
                    e.fired + (TypoGuard.NearMiss(shown, wrongLayout, Real) ? 1 : 0));
            }
            _out.WriteLine($"near-miss false alarms while in {wrongLayout}:");
            foreach (var (len, v) in byLen)
                _out.WriteLine($"    len {len,2}: {v.fired,3}/{v.total,3} ({100.0 * v.fired / v.total,5:F1}%)");
        }
    }

    [Fact]
    public void Precision_and_recall_on_natural_text()
    {
        // ---- RECALL: the whole word typed in the wrong layout, which is what the app is for.
        foreach (var (corpus, wrongLayout, want) in new[]
                 { (UkCorpus, "en", "uk"), (EnCorpus, "uk", "en") })
        {
            var r = Resolver(wrongLayout);
            int total = 0, fixedUp = 0, deferred = 0, vetoed = 0, other = 0;
            var missed = new List<string>();
            foreach (var w in Words(corpus))
            {
                var keys = KeysFor(w);
                if (keys is null) continue;
                total++;
                switch (r.Evaluate(keys, false))
                {
                    case Outcome.Convert c when c.Decision.TargetLayoutId == want: fixedUp++; break;
                    // Held for the phrase to settle. In a sentence the next word converts it; alone in
                    // a search box it stays put until the trigger is pressed.
                    case Outcome.Defer: deferred++; goto default;
                    // Read as a fumble of the language being typed in rather than as a layout error.
                    case Outcome.Keep when TypoGuard.NearMiss(
                            SoftGates.LetterCore(r.RenderCurrent(keys)!).ToLowerInvariant(),
                            wrongLayout, Real): vetoed++; goto default;
                    default:
                        if (missed.Count < 25) missed.Add(w);
                        break;
                }
            }
            other = total - fixedUp - deferred - vetoed;
            _out.WriteLine($"RECALL  {want} typed while in {wrongLayout}, word in isolation: " +
                           $"{fixedUp}/{total} fixed ({100.0 * fixedUp / total:F1}%) — " +
                           $"{deferred} held for the phrase, {vetoed} read as a typo, {other} ambiguous/none");
            _out.WriteLine("   missed: " + string.Join(" ", missed));
        }

        // ---- PRECISION: typing in your own language and fumbling. Nothing should convert.
        foreach (var (corpus, own) in new[] { (UkCorpus, "uk"), (EnCorpus, "en") })
        {
            var r = Resolver(own);
            int total = 0, wrong = 0;
            var byLen = new Dictionary<int, (int total, int wrong)>();
            var examples = new List<string>();
            foreach (var w in Words(corpus))
                foreach (var (typo, kind) in TyposOf(w))
                {
                    var keys = KeysFor(typo);
                    if (keys is null || typo.Length < 2) continue;
                    total++;
                    var e = byLen.GetValueOrDefault(typo.Length);
                    bool bad = r.Evaluate(keys, false) is Outcome.Convert;
                    byLen[typo.Length] = (e.total + 1, e.wrong + (bad ? 1 : 0));
                    if (bad)
                    {
                        wrong++;
                        var c = (Outcome.Convert)r.Evaluate(keys, false);
                        if (examples.Count < 20)
                            examples.Add($"{w} -[{kind}]-> {typo} => {c.Decision.Converted} [{c.Decision.TargetLayoutId}]");
                    }
                }
            _out.WriteLine($"PRECISION {own} typos: {wrong}/{total} wrongly converted ({100.0 * wrong / total:F2}%)");
            foreach (var len in byLen.Keys.OrderBy(x => x))
                if (byLen[len].wrong > 0)
                    _out.WriteLine($"     len {len}: {byLen[len].wrong}/{byLen[len].total} ({100.0 * byLen[len].wrong / byLen[len].total:F1}%)");
            foreach (var x in examples) _out.WriteLine("     " + x);
        }
    }
}

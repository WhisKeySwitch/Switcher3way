using System.Text;
using Switcher3way.Core;
using Switcher3way.Dictionaries;
using Xunit;
using Xunit.Abstractions;

namespace Switcher3way.Core.Tests;

/// <summary>
/// Scores the resolver the way the user experiences it: whole paragraphs typed through it word after
/// word, with the layout moving as the app moves it and the phrase memory carrying across words.
///
/// Per-word tests cannot settle the question this fixes. A short word is deliberately left undecided
/// so a later word can settle it, and "later" only exists in a sequence. Judged one word at a time
/// that policy looks like a catastrophic loss of recall; judged over a paragraph it costs nothing.
/// Both scenarios below therefore run as sequences, against the real dictionaries:
///
///   RECOVERY  — you started typing with the wrong layout active. Is the text right when you stop?
///               This is what the app is for, and the precision fix must not cost it anything.
///   DAMAGE    — you are typing in your own language and fumbling keys at a realistic rate. How many
///               words does the app mangle, and how often does it drag the layout away? This is the
///               number that made a user leave: "crap in english layout here and there".
/// </summary>
public class TypingSimulationTests
{
    private readonly ITestOutputHelper _out;
    public TypingSimulationTests(ITestOutputHelper o) => _out = o;

    private static readonly HunspellDictionaryValidator Real = new();

    private const string Keys = "qwertyuiop[]asdfghjkl;'zxcvbnm,.";
    private const string Uk = "йцукенгшщзхїфівапролджєячсмитьбю";
    private const string Ru = "йцукенгшщзхъфывапролджэячсмитьбю";

    private static Dictionary<char, char> Reverse(string layout)
    {
        var m = new Dictionary<char, char>();
        for (int i = 0; i < Keys.Length; i++) m[layout[i]] = Keys[i];
        return m;
    }
    private static readonly Dictionary<char, char> UkToKey = Reverse(Uk);

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

    /// <summary>A catalog whose current layout moves, because in a real session the app moves it.</summary>
    private sealed class MovingCatalog : ILayoutCatalog
    {
        private readonly string[] _ids;
        public string Current;
        public MovingCatalog(string current, params string[] ids) { Current = current; _ids = ids; }
        public IReadOnlyList<Layout> InstalledLayouts() => _ids.Select(i => new Layout(i, i)).ToList();
        public string? CurrentLayoutId() => Current;
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

    /// <summary>
    /// One typing session, driving the real <see cref="NWayResolver"/> and <see cref="PhraseTracker"/>
    /// and reacting to their outcomes as <c>Engine.AutoConvert</c> does — minus the rewriting, which
    /// is the platform's business and not what is under test here.
    /// </summary>
    private sealed class Session
    {
        private readonly MovingCatalog _cat;
        private readonly NWayResolver _r;
        private readonly PhraseTracker _phrase;
        private readonly string _preferred;
        // Mirrors Engine's held-run state: a run of short words all reading as the same language
        // settles the phrase between them, which is the only thing that can rescue a message whose
        // every word is too short to decide on its own.
        private string? _heldLang;
        private int _heldRun;
        private string? _settledLang;
        private const int HeldRunSettles = 2;
        public readonly List<string> Screen = new();
        public int LayoutSwitches;
        /// <summary>Short words left undecided for a later word to settle — the policy's whole bet.</summary>
        public int Deferred;
        /// <summary>Words a later word came back and converted — the bet paying off.</summary>
        public int RetroFixed;

        public Session(string startLayout, string[] installed, string preferred = "uk")
        {
            _cat = new MovingCatalog(startLayout, installed);
            _r = new NWayResolver(_cat, Real, new NoAlways());
            _phrase = new PhraseTracker((keys, layoutId) => _r.Render(keys, layoutId));
            _preferred = preferred;
        }

        private void SwitchTo(string layoutId)
        {
            if (_cat.Current != layoutId) { _cat.Current = layoutId; LayoutSwitches++; }
        }

        private void Apply(IReadOnlyList<TypedKey> keys, string converted, string layoutId,
                           PhraseTracker.WordKind kind, int gen)
        {
            Screen.Add(converted);
            SwitchTo(layoutId);
            _phrase.Record(keys, converted, 1, kind, gen);
        }

        private void Keep(IReadOnlyList<TypedKey> keys, string shown, PhraseTracker.WordKind kind, int gen)
        {
            Screen.Add(shown);
            _phrase.Record(keys, shown, 1, kind, gen);
        }

        /// <summary>Re-render the earlier deferred words into the settled language, as the engine does.</summary>
        private void Retro(string lang, string layoutId)
        {
            var corr = _phrase.BuildCorrection(lang, layoutId);
            if (corr is null) return;
            for (int i = 0; i < corr.CorrectedWords.Count; i++)
            {
                if (Screen[corr.FirstIndex + i] != corr.CorrectedWords[i].ShownText) RetroFixed++;
                Screen[corr.FirstIndex + i] = corr.CorrectedWords[i].ShownText;
            }
            _phrase.Confirm(corr, _phrase.Generation);
        }

        public void Type(string word)
        {
            var keys = KeysFor(word);
            if (keys is null) { Screen.Add(word); return; }
            int gen = _phrase.Generation;
            var shown = _r.RenderCurrent(keys) ?? word;
            var currentLang = _cat.Current!;

            switch (_r.Evaluate(keys, capsLock: false, phraseLang: _phrase.LockedLang ?? _settledLang))
            {
                case Outcome.Keep k:
                    _heldLang = null; _heldRun = 0; _settledLang = null;
                    Keep(keys, shown, k.ValidInCurrent
                            ? new PhraseTracker.WordKind.Locked(currentLang)
                            : new PhraseTracker.WordKind.Neutral(), gen);
                    break;

                case Outcome.Defer defer:
                {
                    Deferred++;
                    Keep(keys, shown, new PhraseTracker.WordKind.Defaulted(currentLang), gen);
                    var only = defer.Winners.Count == 1 ? defer.Winners[0] : null;
                    if (only is null || only.Lang != _heldLang)
                    { _heldLang = only?.Lang; _heldRun = only is null ? 0 : 1; }
                    else _heldRun++;
                    if (_heldRun >= HeldRunSettles && only is not null)
                    {
                        Retro(only.Lang, only.LayoutId);
                        SwitchTo(only.LayoutId);
                        _settledLang = only.Lang;
                        _heldLang = null; _heldRun = 0;
                    }
                    break;
                }

                case Outcome.Convert conv:
                {
                    _heldLang = null; _heldRun = 0; _settledLang = null;
                    var d = conv.Decision;
                    Retro(d.TargetLayoutId, d.TargetLayoutId);
                    Apply(keys, d.Converted, d.TargetLayoutId,
                          new PhraseTracker.WordKind.Locked(d.TargetLayoutId), gen);
                    break;
                }

                case Outcome.Ambiguous amb:
                {
                    _heldLang = null; _heldRun = 0; _settledLang = null;
                    var t = _phrase.LockedLang ?? _preferred;
                    var w = amb.Winners.FirstOrDefault(x => x.Lang == t);
                    if (w is null) { Keep(keys, amb.Original, new PhraseTracker.WordKind.Neutral(), gen); break; }
                    Apply(keys, w.Converted, w.LayoutId, new PhraseTracker.WordKind.Defaulted(w.Lang), gen);
                    break;
                }
            }
        }
    }

    // ------------------------------------------------------------------ scenarios

    private static string[] WordsOf(string corpus) =>
        corpus.Split(new[] { ' ', '\n', '\r', '\t', ',', '.', '!', '?', ';', ':' },
                     StringSplitOptions.RemoveEmptyEntries)
              .Select(w => w.Trim().ToLowerInvariant())
              .Where(w => w.Length >= 2)
              .ToArray();

    /// <summary>Deterministic fumbles at a fixed rate, so a regression shows up as a changed number
    /// rather than as noise.</summary>
    private static string[] WithTypos(string[] words, int oneIn)
    {
        var res = (string[])words.Clone();
        uint seed = 20260821;
        for (int i = 0; i < words.Length; i++)
        {
            seed = seed * 1664525 + 1013904223;
            if (seed % (uint)oneIn != 0 || words[i].Length < 3) continue;
            int at = (int)(seed >> 16) % (words[i].Length - 1);
            res[i] = ((seed >> 8) % 3) switch
            {
                0 => words[i].Remove(at, 1),
                1 => words[i].Insert(at, words[i][at].ToString()),
                _ => Transpose(words[i], at),
            };
        }
        return res;
    }

    private static string Transpose(string w, int at)
    {
        var a = w.ToCharArray();
        (a[at], a[at + 1]) = (a[at + 1], a[at]);
        return new string(a);
    }

    private static bool IsCyrillic(string s) => s.Any(c => (c >= 'а' && c <= 'я') || c is 'і' or 'ї' or 'є');

    /// <summary>
    /// The bet the policy makes, on its own: a phrase that opens with short words. Those are left
    /// alone at the time — nothing yet distinguishes a two-letter Ukrainian word from a two-letter
    /// English one — and the first word long enough to settle the language comes back and converts
    /// them. If this does not hold, deferring short words is simply lost recall.
    /// </summary>
    [Fact]
    public void A_phrase_that_opens_short_is_repaired_by_the_word_that_settles_it()
    {
        // "як ти пишеш" typed with the English layout still active: zr, nb, gbitim.
        var s = new Session("en", new[] { "en", "uk" });
        foreach (var w in new[] { "як", "ти", "пишеш" }) s.Type(w);

        Assert.Equal(2, s.Deferred);                             // the two short words waited
        Assert.Equal(new[] { "як", "ти", "пишеш" }, s.Screen);   // and were fixed once "пишеш" landed
        Assert.True(s.RetroFixed >= 2, $"retro-fixed only {s.RetroFixed}");
    }

    /// <summary>
    /// A short message where no single word is long enough to settle anything — "як ти?" is two
    /// two-letter words. Each is held on arrival, because at that length a dictionary hit means
    /// nothing; but two in a row reading as the same language is evidence in a way that neither is
    /// alone, and that is what converts them. Without this the caution would simply break short
    /// messages, which is most of what people type into a chat box.
    /// </summary>
    [Fact]
    public void A_message_of_only_short_words_is_settled_by_the_words_agreeing()
    {
        var s = new Session("en", new[] { "en", "uk" });
        foreach (var w in new[] { "як", "ти" }) s.Type(w);

        Assert.Equal(2, s.Deferred);
        Assert.Equal(new[] { "як", "ти" }, s.Screen);
    }

    /// <summary>
    /// The reported failure, as a paragraph rather than as a word: type Ukrainian in the Ukrainian
    /// layout, fumble one word in eight, and count what the app breaks. Every mangled word is one the
    /// user has to go back and repair by hand, and every layout switch is the rest of the sentence
    /// arriving in the wrong alphabet.
    /// </summary>
    [Theory]
    [InlineData("en", "uk")]
    [InlineData("en", "uk", "ru")]
    public void Fumbling_your_own_language_changes_nothing(params string[] installed)
    {
        foreach (var (corpus, layout) in new[] { (PrecisionRecallCorpus.Uk, "uk"), (PrecisionRecallCorpus.En, "en") })
        {
            var typed = WithTypos(WordsOf(corpus), oneIn: 8);
            var s = new Session(layout, installed);
            foreach (var w in typed) s.Type(w);

            var mangled = new List<string>();
            for (int i = 0; i < typed.Length; i++)
                if (s.Screen[i] != typed[i]) mangled.Add($"{typed[i]}->{s.Screen[i]}");

            _out.WriteLine($"{layout} in {string.Join("+", installed)}: {typed.Length} words, " +
                           $"{mangled.Count} mangled, {s.LayoutSwitches} layout switches");
            Assert.Empty(mangled);
            Assert.Equal(0, s.LayoutSwitches);
        }
    }

    /// <summary>
    /// The other side of the trade, and the reason the cure cannot simply be "convert less": start
    /// typing with the wrong layout and the whole paragraph must still come out right.
    /// </summary>
    [Theory]
    [InlineData("en", "uk")]
    [InlineData("en", "uk", "ru")]
    public void Typing_a_paragraph_in_the_wrong_layout_still_recovers(params string[] installed)
    {
        var uk = WordsOf(PrecisionRecallCorpus.Uk);
        var s = new Session("en", installed);
        foreach (var w in uk) s.Type(w);
        var leftLatin = s.Screen.Where(x => !IsCyrillic(x)).ToList();

        var en = WordsOf(PrecisionRecallCorpus.En);
        var s2 = new Session("uk", installed);
        foreach (var w in en) s2.Type(w);
        var leftCyrillic = s2.Screen.Where(IsCyrillic).ToList();

        _out.WriteLine($"{string.Join("+", installed)}: uk-in-en left {leftLatin.Count}/{uk.Length} Latin, " +
                       $"en-in-uk left {leftCyrillic.Count}/{en.Length} Cyrillic");
        Assert.Empty(leftLatin);
        Assert.Empty(leftCyrillic);
    }
}

using Switcher3way.Core;
using Switcher3way.Dictionaries;
using Xunit;
using Xunit.Abstractions;

namespace Switcher3way.Core.Tests;

/// <summary>
/// Measures the vowel-less held-word rule against legitimate vowel-less abbreviations with the REAL
/// Hunspell dictionaries: how many of them would the rule convert? It is admitted at zero and at
/// nothing else — it trades precision for recall on the shortest words the app touches. The macOS
/// twin measured 8/76 on 2026-09-08 and the rule shipped switched off; this is the Windows number.
/// </summary>
public class VowelLessHeldWordTests
{
    private readonly ITestOutputHelper _out;
    public VowelLessHeldWordTests(ITestOutputHelper output) => _out = output;

    private static readonly HunspellDictionaryValidator Real = new();

    private const string KeysRow = "qwertyuiop[]asdfghjkl;'zxcvbnm,.";
    private const string Uk      = "йцукенгшщзхїфівапролджєячсмитьбю";
    private const string Ru      = "йцукенгшщзхъфывапролджэячсмитьбю";

    /// <summary>Legitimate vowel-less tokens people type as themselves — the counter-examples.</summary>
    private static readonly Dictionary<string, string[]> Fixture = new()
    {
        ["uk"] = new[] { "хз", "пн", "вт", "ср", "чт", "пт", "сб", "нд", "тд", "тп", "др", "мб", "млн", "грн",
                         "смс", "тчк", "тг", "тк", "кг", "км", "мм", "см", "мс", "тб", "гб" },
        ["ru"] = new[] { "хз", "пн", "вт", "ср", "чт", "пт", "сб", "вс", "тд", "тп", "др", "мб", "млн", "грн",
                         "смс", "тчк", "тг", "тк", "кг", "км", "мм", "см", "мс", "тб", "гб" },
        ["en"] = new[] { "msg", "pwd", "cmd", "src", "dst", "tbd", "btw", "thx", "pls", "rn", "ty", "np",
                         "gg", "brb", "gtg", "tl", "dr", "hr", "mr", "mrs", "st", "pm", "km", "kg", "mm", "px" },
    };

    private sealed class RowCatalog : ILayoutCatalog
    {
        public string Current = "en";
        private static readonly List<Layout> L = new() { new Layout("en", "en"), new Layout("ru", "ru"), new Layout("uk", "uk") };
        public IReadOnlyList<Layout> InstalledLayouts() => L;
        public string CurrentLayoutId() => Current;
        public string? Render(IReadOnlyList<TypedKey> keys, Layout layout)
        {
            var sb = new System.Text.StringBuilder();
            foreach (var k in keys)
            {
                int i = KeysRow.IndexOf((char)k.KeyCode);
                if (i < 0) return null;
                sb.Append(layout.Id switch { "uk" => Uk[i], "ru" => Ru[i], _ => KeysRow[i] });
            }
            return sb.ToString();
        }
    }

    private static List<TypedKey>? KeysFor(string word, string lang)
    {
        var row = lang switch { "uk" => Uk, "ru" => Ru, _ => KeysRow };
        var keys = new List<TypedKey>();
        foreach (var ch in word)
        {
            int i = row.IndexOf(ch);
            if (i < 0) return null;
            keys.Add(new TypedKey(KeysRow[i], Shift: false, Caps: false));
        }
        return keys;
    }

    [Fact]
    public void TheRuleConvertsNoLegitimateAbbreviation()
    {
        var catalog = new RowCatalog();
        var resolver = new NWayResolver(catalog, Real, new FakeAlways());
        int measured = 0;
        var wouldConvert = new List<string>();
        foreach (var (lang, tokens) in Fixture.OrderBy(kv => kv.Key))
        {
            if (!Real.IsAvailable(lang)) continue;
            catalog.Current = lang;
            foreach (var token in tokens)
            {
                var keys = KeysFor(token, lang);
                if (keys is null) continue;
                measured++;
                if (resolver.Evaluate(keys, capsLock: false) is Outcome.Defer d &&
                    NWayResolver.HeldWordSettlesAlone(d.Original, d.Winners, Real.Vowels(lang), enabled: true))
                    wouldConvert.Add($"{lang}:{token}->{d.Winners[0].Converted} [{d.Winners[0].Lang}]");
            }
        }
        // History on this port: 8/76 on 2026-09-08, then 0/76 once the short-word allow-list removed
        // the junk winners (смс→cvc, тг→nu, мс→vc, ср→ch, вс→dc, src→ікс, rn→кт, tl→ед). This port
        // is clean; macOS still measures 2/76 against NSSpellChecker (см→cv), so the shared constant
        // stays off — the rule may only be switched on when BOTH ports measure zero.
        _out.WriteLine($"vowel-less rule: {wouldConvert.Count}/{measured} legitimate abbreviations would convert: {string.Join(", ", wouldConvert)}");
        if (measured == 0) return;   // no dictionaries on this machine — nothing measured
        Assert.Empty(wouldConvert);
    }
}

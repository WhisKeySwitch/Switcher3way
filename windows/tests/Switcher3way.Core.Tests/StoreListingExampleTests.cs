using System.Text;
using Switcher3way.Core;
using Switcher3way.Dictionaries;
using Xunit;

namespace Switcher3way.Core.Tests;

/// <summary>
/// The Store listing shows the app working by example — "type this, get that" — in four languages,
/// and `store-listing.md` sets itself the rule that an example must be checked rather than
/// remembered. That rule has already been broken once inside that file: the Ukrainian and Russian
/// listings kept claiming a physical keyboard was required long after the claim stopped being true.
///
/// A rule a human has to remember on every edit is not a rule, so the examples are pinned here. If
/// a dictionary update or a resolver change stops one of them converting, this fails and the copy
/// gets corrected before it is pasted into Partner Center — rather than after a reader tries it.
///
/// Rendered through the real layout tables, read off Windows with ToUnicodeEx: the Bulgarian
/// example is worthless if it is measured through a layout no Bulgarian has.
/// </summary>
public class StoreListingExampleTests
{
    private const string Keys  = "qwertyuiop[]asdfghjkl;'zxcvbnm,.";
    private const string UkRow = "йцукенгшщзхїфівапролджєячсмитьбю";
    private const string RuRow = "йцукенгшщзхъфывапролджэячсмитьбю";
    private const string BgRow = "луеишщксдзц;ьяаожгтнвмчюйъэфхп,.";   // 0402:00000402, Typewriter/BDS

    private static readonly string Dir = Path.Combine(AppContext.BaseDirectory, "dict");

    private sealed class Cat : ILayoutCatalog
    {
        private readonly string _current;
        public Cat(string current) => _current = current;
        public IReadOnlyList<Layout> InstalledLayouts() =>
            new[] { "en", "uk", "ru", "bg" }.Select(i => new Layout(i, i)).ToList();
        public string? CurrentLayoutId() => _current;
        public string? Render(IReadOnlyList<TypedKey> keys, Layout layout)
        {
            var sb = new StringBuilder();
            foreach (var k in keys)
            {
                int i = Keys.IndexOf(char.ToLowerInvariant((char)k.KeyCode));
                if (i < 0) return null;
                var row = layout.Id switch { "en" => Keys, "uk" => UkRow, "ru" => RuRow, _ => BgRow };
                sb.Append(char.IsUpper((char)k.KeyCode) ? char.ToUpperInvariant(row[i]) : row[i]);
            }
            return sb.ToString();
        }
    }

    private sealed class NoAlways : IAlwaysConvertList { public bool IsAlwaysConvert(string w) => false; }

    private static Outcome Evaluate(string typed, string activeLayout)
    {
        var cat = new Cat(activeLayout);
        var resolver = new NWayResolver(cat, new HunspellDictionaryValidator(Dir), new NoAlways());
        var keys = typed.Select(c => new TypedKey(c, Shift: char.IsUpper(c), Caps: false)).ToList();
        return resolver.Evaluate(keys, capsLock: false, phraseLang: null);
    }

    /// <summary>The hook of the English, Ukrainian and Russian listings.</summary>
    [Fact]
    public void The_listing_hook_converts_ghbdsn_to_privit()
    {
        var outcome = Assert.IsType<Outcome.Convert>(Evaluate("ghbdsn", "en"));
        Assert.Equal("привіт", outcome.Decision.Converted);
        Assert.Equal("uk", outcome.Decision.TargetLayoutId);
    }

    /// <summary>
    /// The hook of the Bulgarian listing. Rendered through Bulgarian (Typewriter), which is what
    /// Windows installs when it is told to add Bulgarian — the phonetic variants map these keys to
    /// something else entirely, so the claim is true of the default layout and only that one.
    /// </summary>
    [Fact]
    public void The_bulgarian_listing_hook_converts_pdeokf_to_zaedno()
    {
        var outcome = Assert.IsType<Outcome.Convert>(Evaluate("pdeokf", "en"));
        Assert.Equal("заедно", outcome.Decision.Converted);
        Assert.Equal("bg", outcome.Decision.TargetLayoutId);
    }

    /// <summary>
    /// The names-and-jargon paragraph, which every listing illustrates with a word no dictionary
    /// contains. Bulgarian uses Linux, because "Всхкй" has no vowel at all and so cannot be a
    /// Bulgarian word, while "Linux" is an ordinary English one — which is exactly the difference
    /// the rescue reads.
    /// </summary>
    [Fact]
    public void The_bulgarian_names_example_is_rescued_from_the_bulgarian_layout()
    {
        Assert.Equal("Всхкй", new Cat("bg").Render(
            "Linux".Select(c => new TypedKey(c, char.IsUpper(c), false)).ToList(), new Layout("bg", "bg")));

        var outcome = Assert.IsType<Outcome.Rescued>(Evaluate("Linux", "bg"));
        Assert.Equal("Linux", outcome.Decision.Converted);
        Assert.Equal("en", outcome.Decision.TargetLayoutId);
    }

    /// <summary>The English listing's own names example, on the layout it names.</summary>
    [Fact]
    public void The_english_names_example_is_rescued_from_the_ukrainian_layout()
    {
        Assert.Equal("Лншм", new Cat("uk").Render(
            "Kyiv".Select(c => new TypedKey(c, char.IsUpper(c), false)).ToList(), new Layout("uk", "uk")));

        var outcome = Assert.IsType<Outcome.Rescued>(Evaluate("Kyiv", "uk"));
        Assert.Equal("en", outcome.Decision.TargetLayoutId);
    }
}

using Switcher3way.Core;
using Switcher3way.Dictionaries;
using Xunit;

namespace Switcher3way.Core.Tests;

public class HunspellValidatorTests
{
    private static string FixturesDir => Path.Combine(AppContext.BaseDirectory, "fixtures");
    private static HunspellDictionaryValidator Validator() => new(FixturesDir);

    [Fact]
    public void Available_forBundledLanguages()
    {
        var v = Validator();
        Assert.True(v.IsAvailable("en"));
        Assert.True(v.IsAvailable("ru"));
        Assert.True(v.IsAvailable("uk"));
        Assert.False(v.IsAvailable("de")); // no de.dic fixture
    }

    [Fact]
    public void FullLocale_isTrimmedToTwoLetters()
    {
        var v = Validator();
        Assert.True(v.IsAvailable("ru-RU"));
        Assert.True(v.IsValidWord("привет", "ru-RU"));
    }

    [Theory]
    [InlineData("hello", "en", true)]
    [InlineData("zzzznotaword", "en", false)]
    [InlineData("привет", "ru", true)]
    [InlineData("собака", "ru", true)]
    [InlineData("привіт", "uk", true)]
    [InlineData("вибачте", "uk", true)]
    [InlineData("привіт", "ru", false)] // uk word not in ru dictionary
    public void IsValidWord(string word, string lang, bool expected) =>
        Assert.Equal(expected, Validator().IsValidWord(word, lang));

    // End-to-end: the real Hunspell validator plugged into the resolver.
    // Physical keys G,H,B,D,T,N → "ghbdtn" (en) / "привет" (ru) / "привет" (uk-as-rendered).
    // With ru dict containing привет but uk not, the winner is unambiguously ru.
    [Fact]
    public void NWayResolver_withHunspell_endToEnd()
    {
        var layouts = new List<Layout> { new("en", "en"), new("ru", "ru"), new("uk", "uk") };
        var renders = new Dictionary<string, string?> { ["en"] = "ghbdtn", ["ru"] = "привет", ["uk"] = "привет" };
        var catalog = new FakeCatalog(layouts, "en", renders);
        var resolver = new NWayResolver(catalog, Validator(), new FakeAlways());

        var d = resolver.Resolve(new[] { new TypedKey(1, false, false) }, capsLock: false);
        Assert.NotNull(d);
        Assert.Equal("ru", d!.TargetLayoutId);   // "привет" is a real ru word, not a uk one in our dicts
        Assert.Equal("привет", d.Converted);
    }
}

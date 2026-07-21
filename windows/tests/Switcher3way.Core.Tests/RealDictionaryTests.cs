using Switcher3way.Core;
using Switcher3way.Dictionaries;
using Xunit;

namespace Switcher3way.Core.Tests;

/// <summary>
/// Smoke tests against the REAL bundled dictionaries (en MIT/BSD, ru BSD, uk MPL-1.1), deployed to
/// the test output via the Dictionaries project's Content. Assertions use only unambiguous words.
/// </summary>
public class RealDictionaryTests
{
    private static readonly HunspellDictionaryValidator Real = new(); // dict/ next to the assembly

    [Fact]
    public void BundledDictionaries_areAvailable()
    {
        Assert.True(Real.IsAvailable("en"));
        Assert.True(Real.IsAvailable("ru"));
        Assert.True(Real.IsAvailable("uk"));
    }

    [Theory]
    [InlineData("hello", "en", true)]
    [InlineData("qwrtplkj", "en", false)]
    [InlineData("привет", "ru", true)]
    [InlineData("qwrtplkj", "ru", false)]
    [InlineData("привіт", "uk", true)]
    [InlineData("qwrtplkj", "uk", false)]
    public void RealWords_validateCorrectly(string word, string lang, bool expected) =>
        Assert.Equal(expected, Real.IsValidWord(word, lang));

    // End-to-end with real dictionaries: keys rendering to a Ukrainian-only word resolve to uk.
    // uk render "привіт" is a real uk word; ru render "привыт" and en render "ghbdsn" are not words.
    [Fact]
    public void NWayResolver_withRealDicts_picksUkraine()
    {
        var layouts = new List<Layout> { new("en", "en"), new("ru", "ru"), new("uk", "uk") };
        var renders = new Dictionary<string, string?> { ["en"] = "ghbdsn", ["ru"] = "привыт", ["uk"] = "привіт" };
        var resolver = new NWayResolver(new FakeCatalog(layouts, "en", renders), Real, new FakeAlways());

        var d = resolver.Resolve(new[] { new TypedKey(1, false, false) }, capsLock: false);
        Assert.NotNull(d);
        Assert.Equal("uk", d!.TargetLayoutId);
        Assert.Equal("привіт", d.Converted);
    }
}

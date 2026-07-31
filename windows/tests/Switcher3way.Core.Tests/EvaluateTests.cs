using Switcher3way.Core;
using Xunit;

namespace Switcher3way.Core.Tests;

public class EvaluateTests
{
    private static readonly List<Layout> Layouts = new()
    {
        new Layout("en", "en"),
        new Layout("ru", "ru"),
        new Layout("uk", "uk"),
    };
    private static readonly TypedKey[] Keys = { new(1, false, false), new(2, false, false) };

    private static NWayResolver Build(Dictionary<string, string?> renders,
                                      Dictionary<string, HashSet<string>> validWords, string current = "en")
    {
        var catalog = new FakeCatalog(Layouts, current, renders);
        var dict = new FakeDict(new[] { "en", "ru", "uk" }, validWords);
        return new NWayResolver(catalog, dict, new FakeAlways());
    }

    [Fact]
    public void Evaluate_singleWinner_isConvert()
    {
        var r = Build(
            renders: new() { ["en"] = "ghbdtn", ["ru"] = "привет", ["uk"] = "привет" },
            validWords: new() { ["ru"] = new() { "привет" } });
        var o = r.Evaluate(Keys, capsLock: false);
        var c = Assert.IsType<Outcome.Convert>(o);
        Assert.Equal("ru", c.Decision.TargetLayoutId);
        Assert.Equal("привет", c.Decision.Converted);
    }

    [Fact]
    public void Evaluate_ukAndRu_isAmbiguousWithBothWinners()
    {
        var r = Build(
            renders: new() { ["en"] = "ghbdtn", ["ru"] = "привет", ["uk"] = "привет" },
            validWords: new() { ["ru"] = new() { "привет" }, ["uk"] = new() { "привет" } });
        var a = Assert.IsType<Outcome.Ambiguous>(r.Evaluate(Keys, capsLock: false));
        Assert.Equal("ghbdtn", a.Original);
        Assert.Equal(new[] { "ru", "uk" }, a.Winners.Select(w => w.Lang).OrderBy(x => x));
    }

    [Fact]
    public void Evaluate_validInCurrent_isKeep()
    {
        var r = Build(
            renders: new() { ["en"] = "hello", ["ru"] = "руддщ", ["uk"] = "руддщ" },
            validWords: new() { ["en"] = new() { "hello" } });
        Assert.IsType<Outcome.Keep>(r.Evaluate(Keys, capsLock: false));
    }

    [Fact]
    public void Evaluate_noTargetLanguage_isKeep()
    {
        var r = Build(
            renders: new() { ["en"] = "qwerty", ["ru"] = "йцукен", ["uk"] = "йцукен" },
            validWords: new()); // nothing valid anywhere
        Assert.IsType<Outcome.Keep>(r.Evaluate(Keys, capsLock: false));
    }

    [Fact]
    public void ManualPlan_ambiguous_promotesPreferredLanguage()
    {
        // ru and uk render differently and are both valid → ambiguous. Preference uk → uk offered first.
        var r = Build(
            renders: new() { ["en"] = "ghbdtn", ["ru"] = "привет", ["uk"] = "привіт" },
            validWords: new() { ["ru"] = new() { "привет" }, ["uk"] = new() { "привіт" } });
        var plan = r.ManualPlan(Keys, capsLock: false, preferredAmbiguityLang: "uk");
        Assert.NotNull(plan);
        Assert.Equal("uk", plan!.Candidates[0].TargetLayoutId);
    }
}

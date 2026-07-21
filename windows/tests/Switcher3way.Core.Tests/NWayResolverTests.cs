using Switcher3way.Core;
using Xunit;

namespace Switcher3way.Core.Tests;

public class NWayResolverTests
{
    // en/ru/uk installed, "en" current, dictionaries available for all three.
    private static readonly List<Layout> Layouts = new()
    {
        new Layout("en", "en"),
        new Layout("ru", "ru"),
        new Layout("uk", "uk"),
    };

    // A few keystrokes; the fake catalog ignores them and returns seeded renders.
    private static readonly TypedKey[] Keys = { new(1, false, false), new(2, false, false) };

    private static NWayResolver Build(
        Dictionary<string, string?> renders,
        Dictionary<string, HashSet<string>> validWords,
        string current = "en",
        IAlwaysConvertList? always = null)
    {
        var catalog = new FakeCatalog(Layouts, current, renders);
        var dict = new FakeDict(new[] { "en", "ru", "uk" }, validWords);
        return new NWayResolver(catalog, dict, always ?? new FakeAlways());
    }

    [Fact]
    public void SingleWinner_switchesToThatLayout()
    {
        // "ghbdtn" (invalid en) → "привет" valid in ru only.
        var r = Build(
            renders: new() { ["en"] = "ghbdtn", ["ru"] = "привет", ["uk"] = "привет" },
            validWords: new() { ["ru"] = new() { "привет" } }); // uk dict does NOT contain it
        var d = r.Resolve(Keys, capsLock: false);
        Assert.NotNull(d);
        Assert.Equal("ru", d!.TargetLayoutId);
        Assert.Equal("привет", d.Converted);
        Assert.Equal("ghbdtn", d.Original);
    }

    [Fact]
    public void Ambiguous_ukAndRu_leftAlone()
    {
        // Valid in BOTH ru and uk → ambiguous → null (precision-first).
        var r = Build(
            renders: new() { ["en"] = "ghbdtn", ["ru"] = "привет", ["uk"] = "привет" },
            validWords: new() { ["ru"] = new() { "привет" }, ["uk"] = new() { "привет" } });
        Assert.Null(r.Resolve(Keys, capsLock: false));
    }

    [Fact]
    public void ValidInCurrentLanguage_leftAlone()
    {
        // "hello" is a real en word → do nothing, even if it renders to something in ru.
        var r = Build(
            renders: new() { ["en"] = "hello", ["ru"] = "руддщ", ["uk"] = "руддщ" },
            validWords: new() { ["en"] = new() { "hello" } });
        Assert.Null(r.Resolve(Keys, capsLock: false));
    }

    [Fact]
    public void AlwaysConvert_overridesDictionaryAndVetoes()
    {
        // ru render not in any dictionary, but it's on the always-convert list → switch anyway.
        var r = Build(
            renders: new() { ["en"] = "ghbdtn", ["ru"] = "превед", ["uk"] = "превед" },
            validWords: new(),
            always: new FakeAlways("превед"));
        var d = r.Resolve(Keys, capsLock: false);
        Assert.NotNull(d);
        Assert.Equal("ru", d!.TargetLayoutId);
        Assert.Equal("превед", d.Converted);
    }

    [Fact]
    public void PunctuationKey_reRendersWholeToken()
    {
        // db,fxnt on en → "вибачте" on uk (the "," key is "б"). Valid uk only → switch, whole token.
        var r = Build(
            renders: new() { ["en"] = "db,fxnt", ["ru"] = "вибачте", ["uk"] = "вибачте" },
            validWords: new() { ["uk"] = new() { "вибачте" } });
        var d = r.Resolve(Keys, capsLock: false);
        Assert.NotNull(d);
        Assert.Equal("uk", d!.TargetLayoutId);
        Assert.Equal("вибачте", d.Converted); // punctuation re-rendered, not trimmed
    }

    [Fact]
    public void TwoLetterMinimum_singleLetterCore_leftAlone()
    {
        // Letter core "я" is a single letter → soft gate rejects → null.
        var r = Build(
            renders: new() { ["en"] = "!", ["ru"] = "я", ["uk"] = "я" },
            validWords: new() { ["ru"] = new() { "я" }, ["uk"] = new() { "я" } });
        Assert.Null(r.Resolve(Keys, capsLock: false));
    }

    [Fact]
    public void ManualPlan_cyclesAllRenders_winnerFirst()
    {
        // Distinct renders in each layout; ru is the dictionary winner → placed first.
        var r = Build(
            renders: new() { ["en"] = "ghbdtn", ["ru"] = "привет", ["uk"] = "привіт" },
            validWords: new() { ["ru"] = new() { "привет" } });
        var plan = r.ManualPlan(Keys, capsLock: false);
        Assert.NotNull(plan);
        Assert.Equal("ghbdtn", plan!.Original);
        Assert.Equal("en", plan.OriginalLayoutId);
        // Two other-layout candidates, ru first (the winner), then uk.
        Assert.Equal(2, plan.Candidates.Count);
        Assert.Equal("ru", plan.Candidates[0].TargetLayoutId);
        Assert.Equal("привет", plan.Candidates[0].Converted);
        Assert.Equal("uk", plan.Candidates[1].TargetLayoutId);
    }

    [Fact]
    public void ManualPlan_dropsDuplicateRenders()
    {
        // ru and uk render identically → only one candidate offered.
        var r = Build(
            renders: new() { ["en"] = "ghbdtn", ["ru"] = "привет", ["uk"] = "привет" },
            validWords: new());
        var plan = r.ManualPlan(Keys, capsLock: false);
        Assert.NotNull(plan);
        Assert.Single(plan!.Candidates);
    }

    [Fact]
    public void ManualPlan_remoteForwardedChars_returnsNull()
    {
        var r = Build(
            renders: new() { ["en"] = "ghbdtn", ["ru"] = "привет", ["uk"] = "привіт" },
            validWords: new());
        var forwarded = new[] { new TypedKey(0, false, false, 'x') };
        Assert.Null(r.ManualPlan(forwarded, capsLock: false));
    }
}

using Switcher3way.Core;
using Xunit;

namespace Switcher3way.Core.Tests;

/// <summary>
/// The six ways a twelve-day macOS field log (2026-08-27..09-08) showed wrong-layout words being left
/// alone, each as the decision the shared core must now make. Twins of the Swift cases in
/// <c>TypoGuardTests</c>, <c>EvaluateTests</c> and <c>VowelLessHeldWordTests</c>, so the two ports
/// keep deciding identically.
/// </summary>
public class FieldLogMissesTests
{
    private static readonly List<Layout> Layouts = new()
    {
        new Layout("en", "en"), new Layout("ru", "ru"), new Layout("uk", "uk"),
    };
    private static readonly TypedKey[] Keys = { new(1, false, false), new(2, false, false) };

    private static (NWayResolver Resolver, FakeDict Dict) Build(
        Dictionary<string, string?> renders, Dictionary<string, HashSet<string>> words, string current)
    {
        var dict = new FakeDict(new[] { "en", "ru", "uk" }, words);
        dict.Alphabets["en"] = "abcdefghijklmnopqrstuvwxyz";
        dict.Alphabets["uk"] = "абвгдеєжзиіїйклмнопрстуфхцчшщьюя";
        dict.Alphabets["ru"] = "абвгдежзийклмнопрстуфхцчшщъыьэюя";
        dict.VowelSets["en"] = "aeiouy"; dict.VowelSets["uk"] = "аеєиіїоуюя"; dict.VowelSets["ru"] = "аеёиоуыэюя";
        return (new NWayResolver(new FakeCatalog(Layouts, current, renders), dict, new FakeAlways()), dict);
    }

    // 1. The near-miss check is consulted only from six letters up.

    [Fact]
    public void FiveLetterWord_isNotSecondGuessedByTheNearMissCheck()
    {
        // "рукую" is one letter from "друкую" AND reads "here" on the US layout. At five letters nearly
        // every string has a real neighbour, so the guard is not consulted and the hit stands.
        var (r, _) = Build(new() { ["uk"] = "рукую", ["ru"] = "рукую", ["en"] = "here" },
                           new() { ["uk"] = new() { "друкую" }, ["en"] = new() { "here" } }, current: "uk");
        var c = Assert.IsType<Outcome.Convert>(r.Evaluate(Keys, capsLock: false));
        Assert.Equal("en", c.Decision.TargetLayoutId);
    }

    [Fact]
    public void SixLetterTypo_isStillReadAsATypo()
    {
        var (r, _) = Build(new() { ["uk"] = "акшутв", ["ru"] = "акшутв", ["en"] = "friend" },
                           new() { ["uk"] = new() { "акшути" }, ["en"] = new() { "friend" } }, current: "uk");
        Assert.Equal(KeepReason.LooksLikeATypo, Assert.IsType<Outcome.Keep>(r.Evaluate(Keys, false)).Reason);
    }

    // 2. The same text in a sibling language switches only the layout.

    [Fact]
    public void SameTextInSiblingLanguage_isALayoutOnlyDecision_whenThePhraseAgrees()
    {
        // "хорошо" typed on uk: Russian, spelled identically, with "хороше" one edit away in Ukrainian.
        // The phrase has already locked to ru — the corroboration a Ukrainian typist never produces.
        var (r, _) = Build(new() { ["uk"] = "хорошо", ["ru"] = "хорошо", ["en"] = "[jhjij" },
                           new() { ["uk"] = new() { "хороше" }, ["ru"] = new() { "хорошо" } }, current: "uk");
        var c = Assert.IsType<Outcome.Convert>(r.Evaluate(Keys, false, phraseLang: "ru"));
        Assert.Equal("ru", c.Decision.TargetLayoutId);
        Assert.True(c.Decision.IsLayoutOnly);
    }

    [Fact]
    public void SameTextWithoutAPhrase_keepsTheLayoutAndSaysWhy()
    {
        // Six letters and four: the rule does not depend on length (даже is адже transposed).
        foreach (var (word, near) in new[] { ("хорошо", "хороше"), ("даже", "адже") })
        {
            var (r, _) = Build(new() { ["uk"] = word, ["ru"] = word, ["en"] = "xx" },
                               new() { ["uk"] = new() { near }, ["ru"] = new() { word } }, current: "uk");
            Assert.Equal(KeepReason.SameTextUncorroborated, Assert.IsType<Outcome.Keep>(r.Evaluate(Keys, false)).Reason);
        }
    }

    [Fact]
    public void ShortWordBand_isJudgedOnTheWinnersCoreToo()
    {
        // "рухх" renders "he[[" — a two-letter core the English dictionary accepts. Held, not converted.
        var (r, _) = Build(new() { ["uk"] = "рухх", ["ru"] = "рухх", ["en"] = "he[[" },
                           new() { ["uk"] = new() { "рух" }, ["en"] = new() { "he" } }, current: "uk");
        Assert.IsType<Outcome.Defer>(r.Evaluate(Keys, false));
    }

    // 3. A token with no letters is not a word anywhere, and short words do not settle the phrase.

    [Fact]
    public void TokenWithoutLetters_isNotAWordAnywhere()
    {
        var (r, _) = Build(new() { ["en"] = "10", ["ru"] = "10", ["uk"] = "10" }, new(), current: "en");
        Assert.Equal(KeepReason.NotAWordAnywhere, Assert.IsType<Outcome.Keep>(r.Evaluate(Keys, false)).Reason);
    }

    [Fact]
    public void OnlyAWordOfFourLettersSettlesThePhrase()
    {
        foreach (var weak in new[] { "e", "wt", "так", "10", "..", "(ok)" }) Assert.False(NWayResolver.SettlesPhrase(weak), weak);
        foreach (var real in new[] { "добре", "hello", "(місто)", "Wort!" }) Assert.True(NWayResolver.SettlesPhrase(real), real);
    }

    // 4. Ambiguity follows the lock only when the lock is a candidate.

    [Fact]
    public void Ambiguity_followsTheLockOnlyWhenItIsACandidate()
    {
        var uk = new Winner("uk", "uk", "печально"); var ru = new Winner("ru", "ru", "печально");
        var byLock = NWayResolver.ResolveAmbiguity(new[] { uk, ru }, "ru", "uk");
        Assert.Equal("ru", byLock!.Value.Winner.Lang); Assert.True(byLock.Value.ByLock);
        var byPref = NWayResolver.ResolveAmbiguity(new[] { uk, ru }, "en", "uk");
        Assert.Equal("uk", byPref!.Value.Winner.Lang); Assert.False(byPref.Value.ByLock);
        Assert.Equal("ru", NWayResolver.ResolveAmbiguity(new[] { uk, ru }, null, "ru")!.Value.Winner.Lang);
        Assert.Null(NWayResolver.ResolveAmbiguity(new[] { uk, ru }, "en", "off"));
    }

    // 5. Contractions pass the gates.

    [Fact]
    public void Contraction_converts()
    {
        var (r, _) = Build(new() { ["uk"] = "нщгєку", ["ru"] = "нщгэку", ["en"] = "you're" },
                           new() { ["en"] = new() { "you're" } }, current: "uk");
        Assert.Equal("you're", Assert.IsType<Outcome.Convert>(r.Evaluate(Keys, false)).Decision.Converted);
    }

    [Fact]
    public void SoftGates_admitInternalJoinersOnly()
    {
        Assert.True(SoftGates.PassesSoftGates("you're", false));
        Assert.True(SoftGates.PassesSoftGates("кто-то", false));
        Assert.True(SoftGates.PassesSoftGates("You’re", false));
        Assert.False(SoftGates.PassesSoftGates("a_b", false));
        Assert.False(SoftGates.PassesSoftGates("a/b", false));
        Assert.False(SoftGates.PassesSoftGates("-abc", false));
        Assert.False(SoftGates.PassesSoftGates("abc'", false));
    }

    // 6. The vowel-less held word: the predicate, and the fact that it is switched off.

    [Fact]
    public void VowelLessHeldWord_predicate()
    {
        var on = new[] { new Winner("en", "en", "on") };
        Assert.True(NWayResolver.HeldWordSettlesAlone("щт", on, "аеєиіїоуюя", enabled: true));
        Assert.False(NWayResolver.HeldWordSettlesAlone("туц", new[] { new Winner("en", "en", "new") }, "аеєиіїоуюя", enabled: true), "has a vowel");
        Assert.False(NWayResolver.HeldWordSettlesAlone("nfr", new[] { new Winner("uk", "uk", "так"), new Winner("ru", "ru", "так") }, "aeiouy", enabled: true), "ambiguous");
        Assert.False(NWayResolver.HeldWordSettlesAlone("хз", new[] { new Winner("ru", "ru", "хз") }, "аеєиіїоуюя", enabled: true), "same text");
        Assert.False(NWayResolver.HeldWordSettlesAlone("щт", on, "", enabled: true), "unknown vowels: cannot call it vowel-less");
        Assert.False(NWayResolver.HeldWordSettlesAlone("щт", on, "аеєиіїоуюя"), "switched off until the measurement admits it");
        Assert.False(NWayResolver.VowelLessHeldWordEnabled);
    }
}

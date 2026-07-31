using Switcher3way.Core;
using Xunit;
using Kind = Switcher3way.Core.PhraseTracker.WordKind;

namespace Switcher3way.Core.Tests;

public class PhraseTrackerTests
{
    // One-key words; the render func maps (first keycode, layoutId) → rendered text.
    private static TypedKey[] W(int code) => new[] { new TypedKey(code, false, false) };

    private static PhraseTracker Make(Dictionary<(int, string), string> renders) =>
        new((keys, layoutId) => renders.TryGetValue((keys[0].KeyCode, layoutId), out var s) ? s : null);

    [Fact]
    public void LockedLang_reflectsFirstLockedWord()
    {
        var t = Make(new());
        t.Record(W(1), "дом", 1, new Kind.Neutral());
        Assert.Null(t.LockedLang);
        t.Record(W(2), "привет", 1, new Kind.Locked("ru"));
        Assert.Equal("ru", t.LockedLang);
    }

    [Fact]
    public void BuildCorrection_reConvertsEarlierDefaultedWord()
    {
        // Word defaulted to uk; a later ru-only word disambiguates → re-render the uk word into ru.
        var t = Make(new() { [(1, "ru-layout")] = "добрэ" });
        t.Record(W(1), "добре", 1, new Kind.Defaulted("uk"));
        var c = t.BuildCorrection("ru", "ru-layout");
        Assert.NotNull(c);
        Assert.Equal(0, c!.FirstIndex);
        Assert.Equal("добре ", c.OldSegment);
        Assert.Equal("добрэ ", c.NewSegment); // re-rendered into ru, trailing space preserved
    }

    [Fact]
    public void BuildCorrection_neutralWordsReproducedVerbatim()
    {
        var t = Make(new() { [(2, "ru-layout")] = "добрэ" });
        t.Record(W(1), "он", 1, new Kind.Neutral());        // typed correctly, kept
        t.Record(W(2), "добре", 1, new Kind.Defaulted("uk"));
        var c = t.BuildCorrection("ru", "ru-layout");
        Assert.NotNull(c);
        Assert.Equal(1, c!.FirstIndex);                     // starts at the first defaulted-other word
        Assert.Equal("добре ", c.OldSegment);
        Assert.Equal("добрэ ", c.NewSegment);
    }

    [Fact]
    public void BuildCorrection_contradictoryLock_returnsNull()
    {
        var t = Make(new() { [(2, "ru-layout")] = "x" });
        t.Record(W(1), "тест", 1, new Kind.Locked("uk"));   // phrase locked to uk
        t.Record(W(2), "добре", 1, new Kind.Defaulted("uk"));
        Assert.Null(t.BuildCorrection("ru", "ru-layout"));  // can't correct toward ru
    }

    [Fact]
    public void BuildCorrection_nothingDefaultedToOther_returnsNull()
    {
        var t = Make(new());
        t.Record(W(1), "он", 1, new Kind.Neutral());
        t.Record(W(2), "добре", 1, new Kind.Defaulted("ru")); // already ru
        Assert.Null(t.BuildCorrection("ru", "ru-layout"));
    }

    [Fact]
    public void BuildCorrection_overLengthCap_returnsNull()
    {
        var t = Make(new() { [(1, "ru-layout")] = "x" });
        t.Record(W(1), new string('a', PhraseTracker.MaxCorrectionLength + 1), 1, new Kind.Defaulted("uk"));
        Assert.Null(t.BuildCorrection("ru", "ru-layout"));
    }

    [Fact]
    public void Record_withStaleGeneration_isDropped()
    {
        var t = Make(new());
        int gen = t.Generation;
        t.Reset(); // bumps generation
        t.Record(W(1), "x", 1, new Kind.Neutral(), ifGeneration: gen);
        Assert.Empty(t.Words);
    }

    [Fact]
    public void Confirm_updatesMemoryToCorrectedWords()
    {
        var t = Make(new() { [(1, "ru-layout")] = "добрэ" });
        t.Record(W(1), "добре", 1, new Kind.Defaulted("uk"));
        int gen = t.Generation;
        var c = t.BuildCorrection("ru", "ru-layout")!;
        t.Confirm(c, gen);
        Assert.Equal("добрэ", t.Words[0].ShownText);
        Assert.Equal("ru", Assert.IsType<Kind.Defaulted>(t.Words[0].Kind).Lang);
    }

    [Fact]
    public void NoteExtraSpace_incrementsLastWordSpaces()
    {
        var t = Make(new());
        t.Record(W(1), "он", 1, new Kind.Neutral());
        t.NoteExtraSpace();
        Assert.Equal(2, t.Words[0].SpacesAfter);
    }
}

using Switcher3way.Core;
using Xunit;

namespace Switcher3way.Core.Tests;

public class SoftGatesTests
{
    [Theory]
    [InlineData("привет", true)]   // normal word
    [InlineData("hi", true)]       // 2-letter minimum met
    [InlineData("я", false)]       // single letter — too ambiguous
    [InlineData("a", false)]
    [InlineData("", false)]
    [InlineData("ab1", false)]     // contains a digit
    [InlineData("db,fx", false)]   // contains punctuation (a raw render, not a letter core)
    [InlineData("USB", false)]     // all-caps acronym
    [InlineData("camelCase", false)] // internal capital → code identifier
    [InlineData("PascalCase", false)]
    public void PassesSoftGates_capsOff(string typed, bool expected) =>
        Assert.Equal(expected, SoftGates.PassesSoftGates(typed, capsLock: false));

    [Fact]
    public void MixedLatinCyrillic_isRejected() =>
        Assert.False(SoftGates.PassesSoftGates("pривет", capsLock: false)); // Latin p + Cyrillic

    [Fact]
    public void AllCaps_allowed_underCapsLock()
    {
        // Under Caps Lock, all-caps and camelCase vetoes are suppressed (everything is uppercase).
        Assert.False(SoftGates.PassesSoftGates("ПРИВЕТ", capsLock: false));
        Assert.True(SoftGates.PassesSoftGates("ПРИВЕТ", capsLock: true));
    }

    [Theory]
    [InlineData("привет", "привет")]     // nothing to trim
    [InlineData("(привет)", "привет")]   // edge punctuation trimmed
    [InlineData("привет!", "привет")]
    [InlineData("«там»", "там")]
    [InlineData("db,fxnt", "db,fxnt")]   // INTERNAL punctuation is kept (only edges trimmed)
    [InlineData("...", "")]              // no letters
    public void LetterCore_trimsEdgesOnly(string input, string expected) =>
        Assert.Equal(expected, SoftGates.LetterCore(input));
}

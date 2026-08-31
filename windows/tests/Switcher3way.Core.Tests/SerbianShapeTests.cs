using Switcher3way.Core;
using Switcher3way.Dictionaries;
using Xunit;
using Xunit.Abstractions;

namespace Switcher3way.Core.Tests;

/// <summary>
/// Serbian breaks the assumption every other supported language satisfies: that a word contains a
/// vowel. Through syllabic R, <c>крв</c> (blood), <c>прст</c> (finger), <c>врх</c> (top),
/// <c>смрт</c> (death) are ordinary, frequent words with none.
///
/// That matters in the dangerous direction. <c>WordShape.IsPlausible</c> answering "no" for correctly
/// typed Serbian means the resolver reads it as gibberish, and the gibberish rescue may then convert
/// it into another language — a false conversion, which costs the user the rest of the sentence.
///
/// Two fixes are available and they are not obviously equivalent, so this measures both rather than
/// choosing on taste, the way the typo-guard thresholds were settled:
///
///   widen  — add р to the Serbian vowel set. Simple, but р then also breaks consonant runs, so
///            clusters that should look implausible may pass.
///   rule   — keep the vowel set, and accept a vowel-less word that carries an р. Narrower.
///
/// Scored on both sides at once: real Serbian words that must be judged plausible, and non-Serbian
/// strings that must not be.
/// </summary>
public class SerbianShapeTests
{
    private readonly ITestOutputHelper _out;
    public SerbianShapeTests(ITestOutputHelper o) => _out = o;

    private const string Plain = "аеиоу";
    private const string Widened = "аеиоур";

    /// <summary>The narrower option: a vowel-less word carrying an р is a normal Serbian word.</summary>
    private static bool RuleOption(string w) =>
        WordShape.IsPlausible(w, Plain, "sr") || (w.Contains('р') && NoRunTooLong(w, Plain));

    private static bool NoRunTooLong(string w, string vowels)
    {
        int run = 0;
        foreach (var ch in w)
        {
            if (vowels.Contains(ch) || ch == 'р') run = 0;
            else if (++run > WordShape.MaxConsonantRun) return false;
        }
        return true;
    }

    [Fact]
    public void Syllabic_r_options_are_measured_not_chosen()
    {
        var dictDir = Path.Combine(AppContext.BaseDirectory, "dict");
        if (!File.Exists(Path.Combine(dictDir, "sr.dic")))
        {
            _out.WriteLine("Serbian dictionary not bundled yet — skipping");
            return;
        }
        var dict = new HunspellDictionaryValidator(dictDir);

        // MUST be plausible: real Serbian, sampled from the dictionary itself.
        var serbian = File.ReadLines(Path.Combine(dictDir, "sr.dic")).Skip(1)
            .Select(l => l.Split('/')[0].Split('\t')[0].Trim().ToLowerInvariant())
            .Where(w => w.Length >= 3 && w.All(c => c >= 'а' && c <= 'џ'))
            .Take(30000).ToList();

        // MUST NOT be plausible: keyboard gibberish. Not "words of another language" — Russian and
        // Ukrainian words are shaped exactly like Serbian ones and passed this test at 86%, which is
        // correct behaviour and measures nothing. What the rescue is actually shown is a Latin word
        // typed on a Cyrillic layout, so that is what the control has to be.
        const string Latin = "qwertyuiop[]asdfghjkl;'zxcvbnm,.";
        const string Cyr   = "љњертзуиопшђ"
                           + "асдфгхјклчћж"
                           + "џцвбнм,.";
        var notSerbian = File.ReadLines(Path.Combine(dictDir, "en.dic")).Skip(1)
            .Select(x => x.Split('/')[0].Trim().ToLowerInvariant())
            .Where(w => w.Length >= 3 && w.All(c => c >= 'a' && c <= 'z'))
            .Take(20000)
            .Select(w => new string(w.Select(c => Latin.IndexOf(c) >= 0 ? Cyr[Latin.IndexOf(c)] : c).ToArray()))
            .Where(w => !dict.IsValidWord(w, "sr"))
            .ToList();

        _out.WriteLine($"  Serbian words: {serbian.Count}   non-Serbian control: {notSerbian.Count}");
        _out.WriteLine("");
        _out.WriteLine("                       real Serbian judged      non-Serbian wrongly");
        _out.WriteLine("  option               implausible (bad)        judged Serbian (bad)");

        var options = new (string Name, Func<string, bool> F)[]
        {
            ("today (vowels аеиоу)", w => WordShape.IsPlausible(w, Plain, "sr")),
            ("widen (add р)       ", w => WordShape.IsPlausible(w, Widened, "sr")),
            ("rule  (vowel-less+р)", RuleOption),
        };
        foreach (var (name, f) in options)
        {
            int missed = serbian.Count(w => !f(w));
            int wrong = notSerbian.Count(f);
            _out.WriteLine($"  {name}   {missed,6} ({100.0 * missed / serbian.Count,5:F2}%)"
                           + $"          {wrong,6} ({100.0 * wrong / notSerbian.Count,5:F2}%)");
        }

        _out.WriteLine("");
        _out.WriteLine("  the words that motivated this:");
        foreach (var w in new[] { "крв", "прст", "врх", "трг", "црн", "брз", "крст", "врт", "смрт" })
            _out.WriteLine($"    {w,-6} today={WordShape.IsPlausible(w, Plain, "sr"),-5} "
                           + $"widen={WordShape.IsPlausible(w, Widened, "sr"),-5} rule={RuleOption(w)}");
    }
}

using Switcher3way.Dictionaries;
using Xunit;

namespace Switcher3way.Core.Tests;

/// <summary>
/// Quality fixture for the bundled dictionaries (task 3.2 of the Windows MVP).
///
/// The original plan was to diff these against macOS <c>NSSpellChecker</c>, which needs a Mac. This is
/// the portable half of that idea and the more useful one: a checked-in word set covering the categories
/// where a dictionary miss actually changes what the user sees, so a dictionary swap cannot regress them
/// unnoticed.
///
/// Both error directions matter, in opposite ways:
///   * a **false reject** (a real word the dictionary does not know) means the fix silently never happens;
///   * a **false accept** (nonsense the dictionary blesses) is worse — it makes the resolver think the
///     input is already valid, or valid in two languages, and either skips the fix or corrupts good text.
///
/// Words are chosen to be unambiguous members of their category. Anything genuinely valid in both
/// Ukrainian and Russian lives in <see cref="AmbiguousAcrossUkAndRu"/> and is asserted as such, because
/// the resolver's ambiguity path depends on that being true.
/// </summary>
public class DictionaryQualityTests
{
    private static readonly HunspellDictionaryValidator Dict = new();

    // ---- must be accepted: a false reject here is a conversion that never happens ----------------

    public static TheoryData<string, string> ShouldAccept() => new()
    {
        // en — everyday words, including the short ones the 2-letter gate allows
        { "en", "hello" }, { "en", "world" }, { "en", "thanks" }, { "en", "please" },
        { "en", "meeting" }, { "en", "tomorrow" }, { "en", "because" }, { "en", "keyboard" },
        { "en", "of" }, { "en", "in" }, { "en", "it" }, { "en", "we" },
        { "en", "cats" }, { "en", "running" }, { "en", "quickly" },   // inflected/derived

        // ru — nominative plus inflected forms, where Slavic dictionaries most often fall short
        { "ru", "привет" }, { "ru", "спасибо" }, { "ru", "пожалуйста" }, { "ru", "здравствуйте" },
        { "ru", "работа" }, { "ru", "работы" }, { "ru", "работе" }, { "ru", "работой" },
        { "ru", "хорошо" }, { "ru", "сегодня" }, { "ru", "вопрос" }, { "ru", "письмо" },
        { "ru", "ещё" }, { "ru", "её" },                              // ё must not break lookup
        { "ru", "еще" }, { "ru", "ее" }, { "ru", "все" },              // …and neither must omitting it,
                                                                      // which is how most people type
        { "ru", "делаю" }, { "ru", "сделаны" }, { "ru", "говорит" },   // conjugated
        { "ru", "хорошего" }, { "ru", "большие" },                     // declined adjectives
        { "ru", "компьютер" }, { "ru", "интернет" }, { "ru", "пароль" },
        { "ru", "Москва" }, { "ru", "Украина" },
        { "ru", "не" }, { "ru", "он" }, { "ru", "мы" },

        // uk — including the letters that distinguish Ukrainian: і ї є ґ, and the apostrophe
        { "uk", "привіт" }, { "uk", "дякую" }, { "uk", "будь" }, { "uk", "ласка" },
        { "uk", "робота" }, { "uk", "роботи" }, { "uk", "роботі" },
        { "uk", "їжа" }, { "uk", "єдиний" }, { "uk", "ґрунт" }, { "uk", "інший" },
        { "uk", "комп'ютер" }, { "uk", "п'ять" }, { "uk", "з'їзд" },    // apostrophe forms
        { "uk", "роблю" }, { "uk", "зроблено" }, { "uk", "великі" },
        { "uk", "інтернет" }, { "uk", "пароль" },
        { "uk", "Київ" }, { "uk", "Україна" }, { "uk", "Львів" },
        { "uk", "питання" }, { "uk", "сьогодні" }, { "uk", "вибачте" },
        { "uk", "не" }, { "uk", "ми" },
    };

    [Theory]
    [MemberData(nameof(ShouldAccept))]
    public void RealWords_areAccepted(string lang, string word) =>
        Assert.True(Dict.IsValidWord(word, lang), $"'{word}' should be a valid {lang} word");

    // Known gap, deliberately not asserted: the en_US (SCOWL) dictionary does not contain "Kyiv", and
    // proper nouns generally are thin in English while the ru/uk dictionaries do carry Москва, Київ,
    // Україна, Львів. A name the dictionary does not know simply never gets auto-fixed; the manual
    // trigger still converts it, and the always-convert list exists for words worth forcing. Measured
    // 5 August 2026: 170/171 of this accept set pass, the single failure being Kyiv.

    // ---- must be rejected: a false accept here breaks or skips a conversion ----------------------

    public static TheoryData<string, string> ShouldReject() => new()
    {
        // What an English word looks like when typed on a Cyrillic layout. The resolver only converts
        // when exactly one language accepts the input, so these must all be rejected.
        { "ru", "руддщ" },      // hello
        { "ru", "цщкдв" },      // world
        { "ru", "ьууештп" },    // meeting
        { "ru", "ерфтлы" },     // thanks
        { "ru", "вщцтдщфв" },   // download
        { "uk", "руддщ" },
        { "uk", "цщкдв" },
        { "uk", "ерфтлы" },

        // …and the reverse: Cyrillic words typed on a US layout.
        { "en", "ghbdsn" },     // привіт
        { "en", "ghbdtn" },     // привет
        { "en", "cgfcb,j" },    // спасибо
        { "en", "gj;fkeqcnf" }, // пожалуйста
        { "en", "db,fxnt" },    // вибачте
        { "en", "lzrf" },       // дяка

        // Cross-language: Ukrainian-only letters must not pass as Russian, and vice versa.
        { "ru", "привіт" },     // і is not Russian
        { "ru", "їжа" },
        { "ru", "ґрунт" },

        // Outright nonsense in every language.
        { "en", "qwrtplkj" }, { "ru", "фыво" }, { "uk", "фыво" },
        { "en", "zxcvbnm" }, { "ru", "ъъъь" }, { "uk", "ььъї" },
    };

    [Theory]
    [MemberData(nameof(ShouldReject))]
    public void NonWords_areRejected(string lang, string word) =>
        Assert.False(Dict.IsValidWord(word, lang), $"'{word}' should NOT be a valid {lang} word");

    // ---- genuinely ambiguous: the resolver's uk/ru preference path depends on this ---------------

    public static TheoryData<string> AmbiguousAcrossUkAndRu() => new()
    {
        "там", "добре", "собака", "мама", "вода", "море",
    };

    [Theory]
    [MemberData(nameof(AmbiguousAcrossUkAndRu))]
    public void AmbiguousWords_areValidInBoth(string word)
    {
        Assert.True(Dict.IsValidWord(word, "uk"), $"'{word}' should be valid Ukrainian");
        Assert.True(Dict.IsValidWord(word, "ru"), $"'{word}' should be valid Russian");
    }

    // ---- case handling: the app converts words the user typed capitalised or in caps -------------

    [Theory]
    [InlineData("en", "Hello")]
    [InlineData("en", "HELLO")]
    [InlineData("ru", "Привет")]
    [InlineData("ru", "ПРИВЕТ")]
    [InlineData("uk", "Привіт")]
    [InlineData("uk", "ПРИВІТ")]
    public void CasedWords_areAccepted(string lang, string word) =>
        Assert.True(Dict.IsValidWord(word, lang), $"'{word}' should be valid {lang} regardless of case");
}

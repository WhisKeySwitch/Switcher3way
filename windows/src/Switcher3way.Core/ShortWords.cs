namespace Switcher3way.Core;

/// <summary>
/// Which short words a dictionary's verdict may be believed about.
///
/// Under four letters a dictionary hit carries almost no information: 160 of the 676 two-letter
/// Latin strings are in the English dictionary, and nearly all of them are abbreviations, obsolete
/// forms and Scrabble vocabulary nobody types as a word. <see cref="NWayResolver.UndecidableBelow"/>
/// already refuses to <em>convert</em> on such a hit — but the hit is consulted a second way, and
/// that one had no guard at all: a word valid in the language being typed is kept outright, before
/// length is ever considered. So one piece of dictionary noise stops the fix.
///
/// That is the defect a macOS user reported as "it keeps converting це into wt". The app converted
/// nothing: they typed Ukrainian with the English layout active, <c>це</c> landed as <c>wt</c>, and
/// the spell checker calls <c>wt</c> an English word — so the resolver reported "already a word in
/// this layout's language" and left it. Field log 2026-08-27..09-09: <c>wt</c> for це 8 times,
/// <c>ye</c> for ну 5, plus Hey/Рун, key/лун, elm/Будь.
///
/// So for short words the dictionary is not asked alone: the word must also be one this language's
/// speakers actually type. An allow-list rather than a list of junk, because the junk is unbounded
/// (any of 676 two-letter strings) while the real short words of a language are a small closed set.
///
/// <para><b>The two errors are not symmetric.</b> A word missing from the list of the language being
/// <em>typed in</em> stops being "valid here", so a correctly typed word could be converted away —
/// the dangerous direction, gated by the corpus coverage test. A word missing from another
/// language's list only costs one conversion target, which is one trigger tap.</para>
///
/// A language with no list falls through to the dictionary alone, the same fail-open convention as
/// <c>Alphabet</c> and <c>Vowels</c>.
///
/// <para>GENERATED from <c>Sources/Switcher3wCore/ShortWords.swift</c> — the two ports must decide
/// identically, so the data has one source. Edit the Swift file and regenerate.</para>
/// </summary>
public static class ShortWords
{
    /// <summary>
    /// The length below which a dictionary hit needs corroboration from the list. The same four as
    /// <see cref="NWayResolver.UndecidableBelow"/>, for the same measured reason, restated here
    /// because it answers a different question: "is this a word people type", not "is this hit
    /// actionable".
    /// </summary>
    public const int AppliesBelow = 4;

    /// <summary>Is the dictionary's verdict on this word worth believing? Case is ignored.</summary>
    public static bool Admits(string core, string lang)
    {
        if (core.Length >= AppliesBelow) return true;                       // speaks for itself
        var two = lang.Length <= 2 ? lang : lang.Substring(0, 2);
        if (!Common.TryGetValue(two, out var list)) return true;            // no list: fail open
        return list.Contains(core.ToLowerInvariant());
    }

    /// <summary>Does a curated list exist for this language? For diagnostics; <c>Admits</c> fails open.</summary>
    public static bool Covers(string lang) =>
        Common.ContainsKey(lang.Length <= 2 ? lang : lang.Substring(0, 2));

    private static readonly Dictionary<string, HashSet<string>> Common = new()
    {
        ["en"] = new()
        {
        "a", "act", "ad", "add", "age", "ago", "ai", "aid", "aim", "air",
        "all", "am", "an", "and", "any", "api", "app", "are", "arg", "arm",
        "art", "as", "ask", "at", "bad", "bag", "bar", "be", "bed", "bet",
        "big", "bin", "bit", "box", "boy", "bug", "bus", "but", "buy", "by",
        "can", "car", "cat", "cc", "cli", "cmd", "cpu", "css", "csv", "cup",
        "cut", "cv", "day", "db", "dev", "did", "die", "dir", "dj", "dns",
        "do", "doc", "dog", "dst", "eat", "end", "env", "eu", "ex", "exe",
        "eye", "faq", "far", "fee", "few", "fit", "fix", "fly", "for", "ftp",
        "fun", "gap", "gb", "get", "git", "go", "got", "gpu", "gui", "guy",
        "had", "has", "he", "her", "hi", "him", "his", "hit", "hot", "how",
        "hr", "i", "ice", "id", "ide", "if", "ill", "img", "in", "ini",
        "io", "ios", "ip", "is", "it", "its", "job", "jpg", "jwt", "key",
        "kg", "kid", "km", "law", "lay", "leg", "let", "lib", "lie", "log",
        "lot", "low", "mac", "man", "map", "max", "may", "mb", "me", "mid",
        "min", "mix", "ml", "mm", "msg", "my", "net", "new", "no", "nor",
        "not", "now", "npm", "o", "of", "off", "oh", "oil", "ok", "old",
        "on", "one", "ops", "or", "os", "our", "out", "own", "pay", "pc",
        "pdf", "pen", "per", "pet", "php", "pie", "pin", "pm", "png", "pop",
        "pr", "pro", "ps", "put", "pwd", "qa", "ram", "ran", "raw", "red",
        "ref", "rgb", "rid", "row", "run", "sad", "sat", "say", "sdk", "sea",
        "see", "seo", "set", "she", "sit", "six", "so", "son", "sql", "src",
        "ssh", "sso", "sun", "svg", "tab", "tag", "tax", "tb", "tcp", "tea",
        "ten", "the", "tie", "tip", "tmp", "to", "ton", "too", "top", "toy",
        "try", "tv", "two", "txt", "udp", "ui", "uk", "up", "uri", "url",
        "us", "usb", "use", "ux", "var", "via", "vp", "vpn", "vs", "war",
        "was", "way", "we", "web", "wet", "who", "why", "win", "won", "xml",
        "yea", "yes", "yet", "yml", "you", "zip",
        },
        ["uk"] = new()
        {
        "а", "аби", "або", "ага", "аж", "ай", "але", "ані", "ах", "б",
        "без", "би", "бо", "був", "в", "вам", "вас", "ваш", "вже", "ви",
        "все", "всю", "вся", "всі", "від", "гм", "дав", "дай", "два", "де",
        "для", "дня", "дні", "до", "дощ", "дім", "еге", "ех", "ж", "з",
        "за", "зі", "й", "ким", "ко", "код", "кіт", "лев", "ліс", "мав",
        "має", "мед", "ми", "мою", "моя", "мої", "між", "мій", "на", "нам",
        "нас", "наш", "не", "нею", "неї", "ним", "них", "ну", "ні", "ніж",
        "нім", "о", "ой", "ось", "ох", "оце", "оці", "по", "при", "про",
        "під", "рад", "раз", "рот", "рух", "рік", "сад", "сам", "сон", "сім",
        "та", "так", "там", "те", "теж", "ти", "тим", "тих", "то", "той",
        "тою", "тої", "три", "ту", "тут", "ті", "тій", "у", "уже", "усе",
        "усю", "усі", "хай", "хз", "хоч", "хто", "хід", "це", "цей", "цим",
        "цих", "цю", "ця", "ці", "чай", "час", "чек", "чи", "шар", "шум",
        "ще", "що", "щоб", "я", "як", "яка", "яку", "які", "є", "і",
        "іще", "їй", "їм", "їх", "її",
        },
        ["ru"] = new()
        {
        "а", "ага", "ах", "б", "бег", "без", "бы", "был", "в", "вам",
        "вас", "ваш", "во", "вон", "вот", "все", "всю", "вся", "всё", "вы",
        "где", "год", "да", "дай", "дал", "два", "де", "для", "дни", "до",
        "дом", "его", "ее", "ей", "ему", "еще", "ещё", "ею", "её", "ж",
        "за", "и", "из", "или", "им", "их", "к", "как", "кем", "код",
        "кот", "кто", "лев", "лес", "ли", "мал", "мед", "миг", "мне", "мои",
        "мой", "моя", "мы", "мёд", "на", "нам", "нас", "наш", "не", "нем",
        "нет", "ни", "низ", "ним", "них", "но", "нос", "ну", "нём", "о",
        "об", "оба", "ой", "он", "она", "они", "ох", "по", "под", "при",
        "про", "рад", "раз", "рот", "с", "сад", "сам", "со", "сон", "та",
        "так", "там", "те", "тем", "тех", "то", "той", "том", "тот", "три",
        "тут", "ты", "у", "уж", "уже", "фу", "хз", "чай", "час", "чей",
        "чем", "что", "чём", "шар", "шум", "эй", "эта", "эти", "это", "эту",
        "эх", "я", "як",
        },
    };
}

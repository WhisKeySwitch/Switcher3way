import Foundation

/// Which short words a dictionary's verdict may be believed about.
///
/// Under four letters a dictionary hit carries almost no information: 160 of the 676 two-letter
/// Latin strings are in the English dictionary, and nearly all of them are abbreviations, obsolete
/// forms and Scrabble vocabulary that nobody types as a word. `NWayResolver.undecidableBelow`
/// already refuses to *convert* on such a hit — but the hit is also consulted a second way, and
/// that one had no guard at all: a word valid in the language being typed is kept outright, before
/// length is ever considered. So one piece of dictionary noise stops the fix.
///
/// That is the defect a user reported as "it keeps converting це into wt". The app converted
/// nothing: they typed Ukrainian with the English layout active, `це` landed as `wt`, and
/// `NSSpellChecker` calls `wt` an English word — so the resolver reported "already a word in this
/// layout's language" and left it. Field log 2026-08-27..09-09: `wt` for це 8 times, `ye` for ну 5,
/// plus `Hey`/Рун, `key`/лун, `elm`/Будь. Every one of them wrong, and none of them visible on
/// screen as anything but the app doing nothing.
///
/// So for short words the dictionary is not asked alone: the word must also be one this language's
/// speakers actually type. An allow-list rather than a list of junk, because the junk is unbounded
/// (any of 676 two-letter strings) while the real short words of a language are a small closed set.
///
/// **The list is needed on both sides, and the two errors are not symmetric.**
/// - A word missing from the list of the language being *typed in* is no longer "valid here", so a
///   correctly typed word could be converted away. This is the dangerous direction, and it is why
///   these lists are generous and measured against real prose (`ShortWordPrecisionTests`, and the
///   corpus gate in the Windows port). The short-word band limits the blast radius — under four
///   letters the resolver holds rather than converts unless the phrase already agrees — but it does
///   not remove it.
/// - A word missing from *another* language's list only means one fewer conversion target, which
///   costs a trigger tap.
///
/// A language with no list falls through to the dictionary alone, the same fail-open convention as
/// `DictionaryValidating.alphabet(_:)` and `vowels(_:)`: an unlisted language behaves as before
/// rather than having every short word silently vetoed.
public enum ShortWords {

    /// The length below which a dictionary hit needs corroboration from the list. The same four as
    /// `NWayResolver.undecidableBelow`, for the same measured reason, and deliberately restated
    /// here rather than shared: this asks "is this a word people type", not "is this hit actionable".
    public static let appliesBelow = 4

    /// Is the dictionary's verdict on this word worth believing?
    /// `core` is the word's letter core; case is ignored.
    public static func admits(_ core: String, lang: String) -> Bool {
        guard core.count < appliesBelow else { return true }          // long enough to speak for itself
        guard let list = common[String(lang.prefix(2))] else { return true }   // no list: fail open
        return list.contains(core.lowercased())
    }

    /// Does a curated list exist for this language? For diagnostics and tests; `admits` fails open.
    public static func covers(_ lang: String) -> Bool {
        common[String(lang.prefix(2))] != nil
    }

    // MARK: - The lists

    /// Short words people actually type, per language.
    ///
    /// English deliberately excludes the two- and three-letter dictionary noise that caused the
    /// defect — `wt`, `pf`, `ps` is kept but `ye`, `lys`, `oe`, `ee` are not — while including the
    /// abbreviations that are typed daily and meant (`api`, `npm`, `src`, `pwd`, `msg`, `sql`): a
    /// structural rule cannot tell those from noise, but a list can. Ukrainian and Russian carry
    /// their function words in full, because those are the words a mistake here would convert away.
    static let common: [String: Set<String>] = [
        "en": [
            // pronouns, articles, prepositions, conjunctions, particles — the real ones
            "a", "i", "o",
            "am", "an", "as", "at", "be", "by", "do", "go", "he", "hi", "if", "in", "is", "it",
            "me", "my", "no", "of", "oh", "ok", "on", "or", "so", "to", "up", "us", "vs", "we",
            "the", "and", "but", "for", "you", "not", "all", "any", "are", "can", "did", "few",
            "had", "has", "her", "him", "his", "how", "its", "let", "may", "new", "nor", "now",
            "off", "old", "one", "our", "out", "own", "per", "put", "say", "see", "she", "too",
            "top", "try", "two", "use", "via", "was", "way", "who", "why", "yes", "yet", "you",
            // ordinary short nouns and verbs
            "act", "add", "age", "ago", "aid", "aim", "air", "app", "arm", "art", "ask", "bad",
            "bag", "bar", "bed", "bet", "big", "bit", "box", "boy", "bus", "buy", "car", "cat",
            "cup", "cut", "day", "die", "dog", "eat", "end", "eye", "far", "fee", "fit", "fix",
            "fly", "fun", "gap", "get", "got", "guy", "hit", "hot", "ice", "ill", "job", "key",
            "kid", "law", "lay", "leg", "lie", "lot", "low", "man", "map", "mid", "mix", "net",
            "oil", "pay", "pen", "pet", "pie", "pin", "pop", "pro", "ran", "raw", "red", "rid",
            "row", "run", "sad", "sat", "sea", "set", "sit", "six", "son", "sun", "tab", "tax",
            "tea", "ten", "tie", "tip", "ton", "toy", "war", "web", "wet", "win", "won", "yea",
            // abbreviations typed as themselves — daily vocabulary, not noise
            "ad", "ai", "cc", "cv", "db", "dj", "eu", "ex", "gb", "hr", "id", "io", "ip", "kg",
            "km", "mb", "ml", "mm", "os", "pc", "pm", "pr", "ps", "qa", "tb", "tv", "ui", "uk",
            "ux", "vp",
            "api", "arg", "bin", "bug", "cli", "cmd", "cpu", "css", "csv", "dev", "dir", "dns",
            "doc", "dst", "env", "exe", "faq", "ftp", "git", "gpu", "gui", "ide", "img", "ini",
            "ios", "jpg", "jwt", "lib", "log", "mac", "max", "min", "msg", "npm", "ops", "pdf",
            "php", "png", "pwd", "ram", "ref", "rgb", "sdk", "seo", "sql", "src", "ssh", "sso",
            "svg", "tag", "tcp", "tmp", "txt", "udp", "uri", "url", "usb", "var", "vpn", "xml",
            "yml", "zip",
        ],
        "uk": [
            "а", "б", "в", "ж", "з", "і", "й", "о", "у", "я", "є",
            "аж", "ай", "ах", "би", "бо", "ви", "де", "до", "за", "зі", "ех", "гм", "її", "їй",
            "їм", "їх", "ми", "на", "не", "ні", "ну", "ой", "ох", "по", "та", "те", "ти", "то",
            "ті", "це", "ця", "ці", "чи", "ще", "що", "як", "ко",
            "або", "аби", "але", "ані", "без", "був", "вам", "вас", "ваш", "вже", "від", "все",
            "всі", "вся", "дав", "дай", "два", "дні", "для", "дня", "дощ", "має", "мав", "мій",
            "мою", "моя", "мої", "нам", "нас", "наш", "них", "ним", "ніж", "оці", "під", "при",
            "про", "раз", "рік", "рух", "сад", "сам", "сон", "сім", "так", "там", "теж", "тим",
            "тих", "тут", "уже", "усе", "усі", "хай", "хід", "хто", "цим", "цих", "час", "чай",
            "чек", "шар", "шум", "щоб", "яка", "які", "яку", "лев", "ліс", "кіт", "код", "рот",
            "мед", "неї", "між", "три", "дім", "рад", "нею",
            // function words the first run of the tests caught missing, plus the chat shorthand
            // people type as itself (`хз`, `ага`) — an omission here is the dangerous direction.
            "той", "цей", "тої", "тою", "тій", "хоч", "ким", "хз", "ага", "еге", "ось", "оце",
            "іще", "всю", "усю", "цю", "ту", "нім", "тим", "тою", "ким", "дні", "хай",
        ],
        "ru": [
            "а", "б", "в", "ж", "и", "к", "о", "с", "у", "я",
            "ах", "бы", "вы", "во", "да", "де", "до", "ее", "её", "ей", "ею", "за", "из", "их",
            "им", "ли", "мы", "на", "не", "ни", "но", "ну", "об", "ой", "ох", "по", "со", "та",
            "те", "то", "ты", "уж", "фу", "эх", "эй", "як",
            "без", "был", "вам", "вас", "ваш", "вот", "все", "всё", "вся", "где", "дай", "дал",
            "два", "для", "дом", "его", "ему", "еще", "ещё", "или", "как", "кем", "кто", "мне",
            "мой", "моя", "мои", "нам", "нас", "наш", "них", "ним", "оба", "она", "они", "под",
            "при", "про", "раз", "рад", "сам", "три", "тут", "уже", "чей", "чем", "что", "эта",
            "эти", "это", "год", "дни", "час", "чай", "лес", "кот", "рот", "мед", "мёд", "нос",
            "сон", "сад", "шум", "шар", "лев", "код", "бег", "миг", "низ",
            // as above: `так`, `там`, `нет`, `он` are among the most frequent words in the language
            // and their absence would have converted them away.
            "так", "там", "тот", "тем", "той", "том", "тех", "нет", "он", "нём", "нем", "вон",
            "эту", "всю", "хз", "ага", "эта", "чём", "мал", "мой", "два",
        ],
    ]
}

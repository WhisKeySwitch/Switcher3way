import Foundation

/// Every one-, two- and three-letter word that appears in the natural-prose corpus the detection
/// measurements use (`windows/tests/Switcher3way.Core.Tests/Corpus.cs`, extracted verbatim), plus a
/// frequency list for Russian, which that corpus does not cover.
///
/// This is the precision gate on `ShortWords`. An omission there is the dangerous direction: a short
/// word missing from its own language's list stops being "valid where it was typed", and a phrase
/// already settled in another language would then convert it away. So the rule is simple and
/// checkable — if a word turns up in ordinary writing, the list must admit it. The first run of this
/// gate caught `так`, `там`, `нет` and `он` missing from Russian.
enum ShortWordFixture {

    /// Extracted from the Ukrainian corpus with
    /// `words = {w.strip(punct).lower() for w in corpus.split()}; [w for w in words if len(w) <= 3]`
    static let inProse: [String: [String]] = [
        "uk": [
            "а", "або", "але", "без", "бо", "в", "вже", "все", "дні", "до", "дощ", "з", "за", "зі",
            "має", "ми", "між", "мій", "на", "не", "неї", "ні", "ніж", "по", "про", "під", "та",
            "так", "там", "те", "теж", "то", "у", "уже", "це", "ці", "чай", "час", "ще", "що",
            "щоб", "я", "як", "і", "їй", "її",
        ],
        "en": [
            "a", "air", "all", "an", "and", "app", "as", "at", "be", "bus", "but", "by", "can",
            "day", "do", "far", "few", "fix", "for", "had", "has", "how", "i", "if", "in", "is",
            "it", "job", "lot", "me", "my", "not", "of", "off", "old", "on", "or", "pie", "so",
            "ten", "the", "to", "too", "try", "up", "was", "way", "we", "yet", "you",
        ],
        // The most frequent short Russian words, since the corpus has no Russian prose. Function
        // words first, because those are the ones whose loss would be felt in every sentence.
        "ru": [
            "а", "б", "в", "и", "к", "о", "с", "у", "я", "бы", "во", "вы", "да", "до", "ее", "её",
            "ей", "за", "из", "им", "их", "ли", "мы", "на", "не", "ни", "но", "ну", "об", "он",
            "по", "со", "та", "те", "то", "ты", "уж", "без", "был", "вам", "вас", "ваш", "вот",
            "все", "всю", "где", "дай", "два", "для", "дом", "его", "ему", "еще", "ещё", "или",
            "как", "кто", "мне", "мой", "нам", "нас", "наш", "нет", "них", "под", "при", "про",
            "раз", "сам", "так", "там", "тем", "тот", "три", "тут", "уже", "чем", "что", "эта",
            "эти", "это", "эту",
        ],
    ]
}

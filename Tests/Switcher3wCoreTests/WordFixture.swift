import Foundation

/// The checked-in word fixture the dictionary-quality test measures against, mirroring the Windows
/// port's `tests/Switcher3way.Core.Tests/fixtures/*.dic`.
///
/// `valid` are ordinary words a user types every day and that the detector MUST recognise, or
/// wrong-layout input in that language goes unfixed. `invalid` are keyboard mash and cross-layout
/// garbage that must NOT validate, or the detector converts text the user typed on purpose.
///
/// Deliberately unremarkable vocabulary: the point is to catch the validation path changing
/// underneath us, not to explore the edges of any dictionary.
enum WordFixture {

    static let valid: [String: [String]] = [
        "en": [
            "hello", "world", "table", "window", "keyboard", "language", "letter", "morning",
            "please", "answer", "before", "little", "number", "people", "school", "system",
            "water", "yellow", "garden", "picture", "question", "remember", "together", "without",
        ],
        "uk": [
            "привіт", "світ", "стіл", "вікно", "клавіатура", "мова", "літера", "ранок",
            "будь", "відповідь", "перед", "маленький", "число", "люди", "школа", "система",
            "вода", "жовтий", "сад", "картина", "питання", "пам'ять", "разом", "місто",
        ],
        "ru": [
            "привет", "мир", "стол", "окно", "клавиатура", "язык", "буква", "утро",
            "пожалуйста", "ответ", "перед", "маленький", "число", "люди", "школа", "система",
            "вода", "жёлтый", "сад", "картина", "вопрос", "память", "вместе", "город",
        ],
    ]

    static let invalid: [String: [String]] = [
        "en": ["qwzxcv", "ghbdsn", "asdfgh", "zxcvbn", "ktrwbz", "yfgbcfnm", "ghjdthrf", "xtkjdtr"],
        "uk": ["йцукен", "фівапр", "ячсміт", "ґжєїщз", "нзукжз", "фдпоеі", "врмтьб", "щзхїґ"],
        "ru": ["йцукен", "фывапр", "ячсмит", "жэхъё", "нзукжз", "фдпоеы", "врмтьб", "щзхъё"],
    ]

    /// The share of `valid` words a language's dictionary must accept for the test to pass. Below
    /// this the validation path has regressed (or the dictionary is not the one we think it is).
    static let minValidRate = 0.85

    /// The share of `invalid` words that must be rejected.
    static let minRejectRate = 0.85
}

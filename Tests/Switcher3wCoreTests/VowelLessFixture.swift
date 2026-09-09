import Foundation

/// Legitimate vowel-less tokens people type as themselves, per language — the words the vowel-less
/// held-word rule must NOT convert. The rule says: a two- or three-letter word held for the phrase,
/// reading as exactly one other language, with no vowel in the language it was typed in, is keyboard
/// noise there and may convert at once. These are the counter-examples: abbreviations of weekdays,
/// units, and chat shorthand that have no vowel and are nevertheless meant exactly as typed. The
/// measurement in `VowelLessHeldWordTests` counts how many of them the rule would convert; the rule
/// is admitted only at zero. Grow the list freely — every addition is a stricter test.
enum VowelLessFixture {
    static let tokens: [String: [String]] = [
        // хз (who knows), weekdays пн вт ср чт пт сб нд, т.д./т.п., др (other), мб (maybe),
        // млн/млрд, грн, смс, тчк, тг (Telegram), тк (так как), кг, км, мм, см, мс, тб, гб
        "uk": ["хз", "пн", "вт", "ср", "чт", "пт", "сб", "нд", "тд", "тп", "др", "мб", "млн", "грн",
               "смс", "тчк", "тг", "тк", "кг", "км", "мм", "см", "мс", "тб", "гб"],
        "ru": ["хз", "пн", "вт", "ср", "чт", "пт", "сб", "вс", "тд", "тп", "др", "мб", "млн", "грн",
               "смс", "тчк", "тг", "тк", "кг", "км", "мм", "см", "мс", "тб", "гб"],
        "en": ["msg", "pwd", "cmd", "src", "dst", "tbd", "btw", "thx", "pls", "rn", "ty", "np",
               "gg", "brb", "gtg", "tl", "dr", "hr", "mr", "mrs", "st", "pm", "km", "kg", "mm", "px"],
    ]
}

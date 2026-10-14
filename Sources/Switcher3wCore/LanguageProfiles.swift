import Foundation

/// What the app knows about each language it detects, in one place.
///
/// The resolver works over whatever layouts the user has enabled, so a language needs no plumbing
/// to take part — but without its per-language knowledge it takes part on the dictionary alone:
/// no vowels means no gibberish rescue, no canary means a dictionary episode goes unnoticed, and no
/// short-word list (`ShortWords`) means every two-letter dictionary hit is believed. Every one of
/// those fails open, which was right for three languages and is the reason a profile is required
/// before a language is described as supported.
///
/// The short-word lists stay in `ShortWords.swift`, because the Windows `ShortWords.cs` is
/// generated from that file.
public struct LanguageProfile: Sendable {
    public enum Script: Sendable { case latin, cyrillic }

    /// 2-letter code, as `Layout.lang` spells it.
    public let code: String
    public let script: Script
    /// For `WordShape.isPlausible` and the transliteration check. Lower-case.
    public let vowels: String
    /// For `DictionarySentinel`: a common word the dictionary must accept, and mash it must reject.
    /// The word is chosen to belong to this language only, so a dictionary answering for the wrong
    /// language fails it too.
    public let canary: (word: String, mash: String)
    /// The language's name in itself, for Settings.
    public let nativeName: String

    public static let all: [String: LanguageProfile] = [
        "en": .init(code: "en", script: .latin, vowels: "aeiouy",
                    canary: ("the", "zzqxjw"), nativeName: "English"),
        "uk": .init(code: "uk", script: .cyrillic, vowels: "аеєиіїоуюя",
                    canary: ("привіт", "нзукжз"), nativeName: "Українська"),
        "ru": .init(code: "ru", script: .cyrillic, vowels: "аеёиоуыэюя",
                    canary: ("привет", "нзукжз"), nativeName: "Русский"),
        // ъ is a full vowel in Bulgarian (`път`, `съм`, `къща`), not a sign as in Russian; without
        // it `път` reads as vowel-less. The canary avoids `привет`, which the Bulgarian dictionary
        // accepts.
        "bg": .init(code: "bg", script: .cyrillic, vowels: "аеиоуъюя",
                    canary: ("здравей", "нзукжз"), nativeName: "Български"),
    ]

    public static func of(_ lang: String) -> LanguageProfile? { all[String(lang.prefix(2))] }

    /// Do all these languages write in one script? A tie between them is a choice of language the
    /// preference setting can make; a tie across scripts is a coin toss between unrelated texts.
    public static func shareScript(_ langs: some Collection<String>) -> Bool {
        let scripts = langs.map { of($0)?.script }
        guard let first = scripts.first, let script = first else { return false }
        return scripts.allSatisfy { $0 == script }
    }
}

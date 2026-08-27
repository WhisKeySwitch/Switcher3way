import Foundation

/// The measurement corpus for the gibberish rescue (`NWayResolver`'s no-dictionary-winner path).
///
/// Two sides with opposite contracts:
/// - **keep side**: tokens people really type that no dictionary validates — names, tech
///   vocabulary, slang typed in its OWN layout. The rescue must not touch a single one; a false
///   rescue converts the word AND drags the layout, costing the user the rest of the sentence.
/// - **rescue side**: real jargon, loanwords and names typed in the WRONG layout (each entry from
///   the 2026-08-27 user log or collected since). Missing one costs a manual trigger tap, so this
///   side is a recall report, not a hard gate.
///
/// `RescueQualityTests` drives both sides through the real resolver with the real system
/// dictionaries. The thresholds in `WordShape` / `NWayResolver.rescueFloor` are whatever made the
/// keep side clean while keeping the rescue side worth shipping — change them only together with
/// the numbers recorded in the change's design.md.
enum RescueFixture {

    /// Typed in the English layout, must stay exactly as typed. Deliberately adversarial:
    /// vowel-less tech tokens (`ctrl`, `http`) render into plausible-looking Cyrillic, names with
    /// unusual shapes (`kyiv`) validate nowhere, and `emergancy` is a typo whose one-edit
    /// neighbour is real.
    static let keepEnglish: [String] = [
        "kyiv",         // the log's own proper noun — en-invalid, and its Cyrillic render is noise
        "lviv",         // same shape family
        "ctrl", "html", "http", "https", "smtp", "grpc",   // vowel-less/odd tech tokens, length ≥ 4
        "json", "yaml", "sudo", "grep", "bash", "linux", "github",
        "kubectl", "sqlite", "nginx",
        "peopleops",    // the log's product name (lower-cased: the camel gate must not be the only save)
        "snipeit",      // product name from the log
        "emergancy",    // a typo: near-miss of "emergency" must keep it
        "recieve",      // the classic typo, same contract
        "asap", "lorem", "ipsum",
    ]

    /// Typed in the Ukrainian layout, must stay exactly as typed: Cyrillic slang and
    /// abbreviations no dictionary knows, in their own layout.
    static let keepUkrainian: [String] = [
        "імхо",        // borrowed slang, plausible uk shape → must decline as "plausible in typed"
        "лол",         // below floor anyway; here to prove it stays untouched
        "хзхз",        // vowel-less doubled slang at the floor: gibberish both sides → keep
    ]

    /// Typed on the English layout while meaning Ukrainian/Russian — expected to rescue.
    /// `expectedUk` is the Ukrainian render (the ambiguity default this suite configures);
    /// entries whose uk and ru renders differ still rescue through the same pair.
    static let rescueLatinToCyrillic: [(typed: String, expectedUk: String)] = [
        ("fgrf", "апка"),          // the log: slang for "app"
        ("fqls", "айді"),          // the log: "ID"
        ("ntyfyne", "тенанту"),    // the log: "tenant" (dative)
        ("xtryenb", "чекнути"),    // the log: "to check"
        ("rfibh", "кашир"),        // the log: a name
    ]

    /// Typed on a Cyrillic layout while meaning English — expected to rescue to English.
    static let rescueCyrillicToLatin: [(typedUk: String, expectedEn: String)] = [
        ("лншм", "kyiv"),          // the log's Kyiv case, reversed
        ("дштгч", "linux"),
    ]

    /// The floor of acceptable recall per direction — a report threshold, not a precision gate.
    /// Set from the first real measurement; the point is that a refactor that silently kills the
    /// rescue shows up as a number, not as a user's bug report.
    static let minRescueRecall = 0.6
}

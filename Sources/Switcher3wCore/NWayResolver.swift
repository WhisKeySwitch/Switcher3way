import Foundation

/// N-way layout detection: generalizes the 2-way `LayoutDetector.decide` from a pair to any number
/// of installed layouts (e.g. EN + UK + RU). The typed keycodes are rendered through EVERY layout
/// that has a system dictionary, and the word is validated in that layout's language.
/// Precision-first: switch only when there is exactly one target language.
///
/// Platform services arrive through `LayoutCatalog` / `DictionaryValidating` / `WordExceptionList`
/// so the decision logic is assertable without the app, its permissions, or the machine's
/// particular set of installed layouts.
@MainActor
public final class NWayResolver {

    private let catalog: LayoutCatalog
    private let dict: DictionaryValidating
    private let exceptions: WordExceptionList

    public init(catalog: LayoutCatalog, dict: DictionaryValidating, exceptions: WordExceptionList) {
        self.catalog = catalog
        self.dict = dict
        self.exceptions = exceptions
    }

    /// One candidate: layout + its language + how the input looks in it + whether the word is valid.
    private struct Candidate {
        let layoutID: String
        let lang: String      // 2-letter code (ru/uk/en…)
        let string: String    // keycodes read in this layout
        let isValid: Bool     // string is a real word in the language dictionary
    }

    /// Decision: which layout to switch to and what text to type. nil — leave as is.
    public struct Decision {
        public let targetLayoutID: String
        public let lang: String      // 2-letter code of the target language
        public let original: String
        public let converted: String

        public init(targetLayoutID: String, lang: String, original: String, converted: String) {
            self.targetLayoutID = targetLayoutID
            self.lang = lang
            self.original = original
            self.converted = converted
        }
    }

    /// One language that validates the typed word (returned when more than one does).
    public struct Winner {
        public let lang: String
        public let layoutID: String
        public let converted: String
    }

    /// Why a word was left alone. Every one of these is a decision, and every one is invisible on
    /// screen — so unless it is written down, a guard working perfectly and a guard that never ran
    /// leave behind identical evidence.
    public enum KeepReason: String {
        /// Not a word in any installed language — ordinary for names, code, and typing in progress.
        case notAWordAnywhere
        /// A real word of the language it was typed in. Nothing to fix, and it settles the phrase.
        case validInCurrent
        /// The current layout, or its language, could not be determined.
        case noCurrentLanguage
        /// It reads as another language, but the language being typed holds a word one keystroke
        /// away, so a fumbled key is the simpler explanation. This is the guard that stops typos.
        case looksLikeATypo
        /// Too short to decide alone, and it disagrees with the language the phrase settled into.
        case phraseDisagrees
    }

    /// Full evaluation result. `.ambiguous` carries every validating language so the caller
    /// can resolve it by the preferred-language setting / phrase lock (phrase-aware-ambiguity);
    /// `resolve` collapses it to nil for callers that only care about the unambiguous case.
    public enum Outcome {
        case keep(KeepReason)
        case convert(Decision)
        case ambiguous(original: String, winners: [Winner])
        /// The input reads as another language, but on evidence too weak to act on: a word of two or
        /// three letters, where a dictionary hit means almost nothing. The caller leaves the text
        /// alone and records the keystrokes as defaulted to the current language, so the next word
        /// that does settle the phrase converts this one along with it.
        case held(original: String, winners: [Winner])
        /// No dictionary knows this word, but the typed rendering is gibberish in the typed
        /// language while exactly one candidate is a plausible word shape in its own — jargon or a
        /// name typed in the wrong layout (`Лншм` → `Kyiv`). Weaker evidence than a dictionary hit:
        /// the caller converts but records the word as *defaulted*, not locked, so the phrase can
        /// still overrule it. When the plausible pair is uk/ru the outcome is `.ambiguous` instead,
        /// and the ambiguity preference decides, exactly as for shared dictionary words.
        case rescued(Decision)
    }

    /// Shorter than this, a dictionary hit carries no information: a quarter of all two-letter Latin
    /// strings are in the English dictionary — `ft`, `bf`, `kw`, `lb` — mostly abbreviations. Words
    /// this short are handed to the phrase around them instead of being decided here.
    public static let undecidableBelow = 4

    /// The length from which `TypoGuard.nearMiss` is worth listening to. It asks whether *any*
    /// one-edit neighbour is real, and a word has roughly (alphabet x 2 x length) neighbours, so on
    /// short words it fires on everything. Measured on the Windows port against genuine wrong-layout
    /// typing: 100% false alarms at two letters, 30-40% at four, and 0% from six up, both directions.
    public static let nearMissTrustedFrom = 6

    /// The gibberish rescue acts only from this length up. A rescue candidate carries even less
    /// evidence than a short dictionary hit (no dictionary vouches for it at all), but the words
    /// that motivated the feature — `апка`, `айді`, `Лншм` — are four letters, and below four the
    /// shape signals stop meaning anything: almost any 2–3-letter cluster is a legitimate
    /// abbreviation in one of the languages (`хз`, `пн`, `msg`, `pwd`). Measured in
    /// `RescueQualityTests` against the checked-in fixture.
    public static let rescueFloor = 4

    /// Legacy single-winner view of `evaluate` — nil unless exactly one language matches.
    public func resolve(keys: [TypedKey], capsLock: Bool) -> Decision? {
        if case .convert(let d) = evaluate(keys: keys, capsLock: capsLock) { return d }
        return nil
    }

    /// Renders the input through all layouts-with-dictionary and picks the target.
    /// `.keep` if: the layout/language can't be determined; the word is valid in the
    /// current language; no other language matches. `.ambiguous` when several do.
    /// - Parameter phraseLang: the language the surrounding phrase has already settled into, if any
    ///   (the caller's `PhraseTracker.lockedLang`). It is the tie-breaker for words too short to
    ///   decide alone: with it a two-letter word converts because the phrase says so; without it the
    ///   word waits for one that can settle the question.
    /// - Parameter weighEvidence: whether the precision guards apply. They exist to restrain the app
    ///   from acting on thin evidence of its own initiative, which is not the situation when the user
    ///   has pressed the trigger — an explicit request is entitled to an answer even for a two-letter
    ///   word, so `manualPlan` turns them off.
    public func evaluate(keys: [TypedKey], capsLock: Bool,
                         phraseLang: String? = nil, weighEvidence: Bool = true) -> Outcome {
        guard !keys.isEmpty else { return .keep(.notAWordAnywhere) }

        let layouts = catalog.installedLayouts()
        let currentID = catalog.currentLayoutID()
        guard let currentLayout = layouts.first(where: { $0.id == currentID }) else {
            CoreLog.write("nway: nil — current layout not resolvable (id=\(currentID.components(separatedBy: ".").last ?? "?"), installed=\(layouts.count))")
            return .keep(.noCurrentLanguage)
        }
        let currentLang = String(currentLayout.lang.prefix(2))

        // One candidate per language (several layouts of the same language — e.g. US/ABC — are
        // collapsed, preferring the valid and canonical one). Skip languages without a system dictionary.
        // Validity is judged on the letter "core" — edge punctuation/digits stripped — so that a
        // trailing "!" or a leading "(" doesn't hide an otherwise-valid word.
        var byLang: [String: Candidate] = [:]
        for layout in layouts {
            let lang = String(layout.lang.prefix(2))
            guard dict.isAvailable(lang) else { continue }
            guard let rendered = rendered(keys, in: layout.id) else { continue }
            let valid = dict.isValidWord(SoftGates.letterCore(Array(rendered)).lowercased(), lang: lang)
            if let existing = byLang[lang] {
                if valid && !existing.isValid {   // a valid render outweighs any other
                    byLang[lang] = Candidate(layoutID: layout.id, lang: lang, string: rendered, isValid: true)
                }
            } else {
                byLang[lang] = Candidate(layoutID: layout.id, lang: lang, string: rendered, isValid: valid)
            }
        }

        // Compact candidate dump for diagnosing "keep" decisions (only built when debug log is on).
        let dump = byLang.values
            .sorted { $0.lang < $1.lang }
            .map { "\($0.lang):'\($0.string)'\($0.isValid ? " VALID" : "")" }
            .joined(separator: " ")

        guard let current = byLang[currentLang] else {
            CoreLog.write("nway: nil — no candidate for current lang \(currentLang) [\(dump)]")
            return .keep(.noCurrentLanguage)
        }
        // always-convert — an EXPLICIT user override: if some other language's letter core is in
        // the "always convert" list, switch there even bypassing the dictionary and vetoes.
        for cand in byLang.values where cand.lang != currentLang {
            if exceptions.isAlwaysConvert(SoftGates.letterCore(Array(cand.string))) {
                return .convert(Decision(targetLayoutID: cand.layoutID, lang: cand.lang,
                                         original: current.string, converted: cand.string))
            }
        }

        // Typed correctly in the current language (its letter core is a real word) → do nothing.
        // Report it, rather than merely returning: a real word of the language being typed in is the
        // best evidence the app ever gets about what language this phrase is, and the caller pins it.
        if current.isValid {
            CoreLog.write("nway: nil — '\(current.string)' is a valid \(currentLang) word [\(dump)]")
            return .keep(.validInCurrent)
        }

        // Other languages where the input's letter core is a real word. Only the LETTER core is
        // validated (edge punctuation/digits trimmed), but the whole token is re-rendered in the
        // target layout on output — punctuation keys convert too (the "/" key is "." on the RU/UK
        // PC layouts, the "," key is "б", etc.), because the keystrokes were meant for that layout.
        var winners: [Winner] = []
        for cand in byLang.values where cand.lang != currentLang {
            let core = SoftGates.letterCore(Array(cand.string))
            guard SoftGates.passes(core, capsLock: capsLock) else { continue }
            guard dict.isValidWord(core.lowercased(), lang: cand.lang) else { continue }
            winners.append(Winner(lang: cand.lang, layoutID: cand.layoutID, converted: cand.string))
        }
        // 0 — not wrong-layout. >1 — ambiguous (uk↔ru): reported as such so the caller can
        // apply the preferred-language / phrase-lock policy (phrase-aware-ambiguity).
        if winners.isEmpty {
            // Last resort before keeping: jargon, loanwords and names validate NOWHERE, so a
            // dictionary can never rescue them — but a word typed in the wrong layout is gibberish
            // in the layout it landed in and word-shaped in the one it was meant for, and that
            // asymmetry is checkable. Runs with every gate the dictionary path has, plus its own.
            if let rescue = rescue(current: current, byLang: byLang, capsLock: capsLock, dump: dump) {
                return rescue
            }
            CoreLog.write("nway: nil — no valid target language [\(dump)]")
            return .keep(.notAWordAnywhere)
        }

        // How far the dictionary hit can be trusted depends almost entirely on how long the word is,
        // and the two guards below cover different bands of that. Short words cannot be cross-checked
        // for a typo at all — at that length every string has a near miss — so the phrase arbitrates.
        let coreLength = SoftGates.letterCore(Array(current.string)).count
        if weighEvidence && coreLength < Self.nearMissTrustedFrom {
            if let phraseLang, let byPhrase = winners.first(where: { $0.lang == phraseLang }) {
                CoreLog.write("nway: short word, phrase agrees on \(phraseLang) [\(dump)]")
                return .convert(Decision(targetLayoutID: byPhrase.layoutID, lang: byPhrase.lang,
                                         original: current.string, converted: byPhrase.converted))
            }
            if phraseLang != nil {
                CoreLog.write("nway: nil — too short to decide, phrase reads as another language [\(dump)]")
                return .keep(.phraseDisagrees)
            }
            // Nothing has settled the phrase yet. Under four characters there is no honest way to
            // tell a short Ukrainian word from a short English one, so hold it — unconverted, but
            // with its keystrokes remembered, so the word that does settle the phrase converts this
            // one along with it. That is what stops the caution from being a plain loss of recall.
            if coreLength < Self.undecidableBelow {
                CoreLog.write("nway: held — too short to act on alone [\(dump)]")
                return .held(original: current.string, winners: winners)
            }
            // Four or five characters, with nothing to contradict it: worth acting on.
        }

        // Before accepting "this is a word in another language", check the likelier story: that it is
        // a word of *this* language with one key missed. A fumbled key is a simpler explanation than
        // a keyboard that changed for one word and changed back, and this check was never made.
        if weighEvidence,
           TypoGuard.nearMiss(SoftGates.letterCore(Array(current.string)).lowercased(),
                              lang: currentLang, dict: dict) {
            CoreLog.write("nway: nil — near miss of a \(currentLang) word, reading it as a typo [\(dump)]")
            return .keep(.looksLikeATypo)
        }

        if winners.count > 1 {
            CoreLog.write("nway: ambiguous (\(winners.map(\.lang).sorted().joined(separator: "/"))) [\(dump)]")
            return .ambiguous(original: current.string, winners: winners)
        }
        let winner = winners[0]
        return .convert(Decision(targetLayoutID: winner.layoutID, lang: winner.lang,
                                 original: current.string, converted: winner.converted))
    }

    /// The gibberish rescue: no dictionary validates the word in any language, so the shape of the
    /// renderings is the only evidence left. Convert only when the typed side is gibberish AND a
    /// candidate side is word-shaped — one-sided implausibility is not enough (`npm` is gibberish
    /// in English, but so is its Cyrillic rendering, so it keeps).
    ///
    /// Returns nil when the rescue does not apply; the caller then keeps as before. Every decline
    /// on the way is logged: this path exists precisely where the log used to show nothing.
    private func rescue(current: Candidate, byLang: [String: Candidate],
                        capsLock: Bool, dump: String) -> Outcome? {
        // The dictionary path's own vetoes first, on the UN-lowercased core: the all-caps and
        // camelCase vetoes are about letter case, and lowercasing first would blind them.
        let rawCore = SoftGates.letterCore(Array(current.string))
        guard SoftGates.passes(rawCore, capsLock: capsLock) else { return nil }
        let core = rawCore.lowercased()
        guard core.count >= Self.rescueFloor else {
            CoreLog.write("nway: rescue declined — below length floor [\(dump)]")
            return nil
        }

        // Shape of the typed side. An empty vowel set means this language's shape is unknown —
        // then nothing can be called gibberish and the rescue stays out of the way (fail-open,
        // like the near-miss alphabet).
        let currentVowels = dict.vowels(current.lang)
        guard !currentVowels.isEmpty else { return nil }
        if WordShape.isPlausible(core, vowels: currentVowels, lang: current.lang) {
            CoreLog.write("nway: rescue declined — '\(current.string)' is plausible \(current.lang) [\(dump)]")
            return nil
        }

        // Not a typo either: if the typed language holds a word one keystroke away, a fumbled key
        // stays the simpler story, exactly as on the dictionary path — and it is reported as that
        // story, not as a generic keep.
        if TypoGuard.nearMiss(core, lang: current.lang, dict: dict) {
            CoreLog.write("nway: rescue declined — near miss of a \(current.lang) word [\(dump)]")
            return .keep(.looksLikeATypo)
        }

        // The candidates that ARE word-shaped in their own language.
        var plausible: [Winner] = []
        for cand in byLang.values where cand.lang != current.lang {
            let candCore = SoftGates.letterCore(Array(cand.string)).lowercased()
            let candVowels = dict.vowels(cand.lang)
            guard !candVowels.isEmpty,
                  WordShape.isPlausible(candCore, vowels: candVowels, lang: cand.lang) else { continue }
            plausible.append(Winner(lang: cand.lang, layoutID: cand.layoutID, converted: cand.string))
        }

        switch plausible.count {
        case 0:
            CoreLog.write("nway: rescue declined — gibberish in every language [\(dump)]")
            return nil
        case 1:
            let w = plausible[0]
            CoreLog.write("nway: rescue → \(w.lang) — '\(current.string)' is word-shaped only there [\(dump)]")
            return .rescued(Decision(targetLayoutID: w.layoutID, lang: w.lang,
                                     original: current.string, converted: w.converted))
        default:
            // The uk/ru pair is the ambiguity the preference setting exists for; report it the
            // same way dictionary words shared by both languages are reported. Anything wider —
            // plausible across scripts — is a coin toss, and a wrong pick costs the user the
            // sentence while a keep costs one trigger tap.
            let langs = Set(plausible.map(\.lang))
            if langs == ["ru", "uk"] {
                CoreLog.write("nway: rescue ambiguous (ru/uk) — word-shaped in both [\(dump)]")
                return .ambiguous(original: current.string, winners: plausible)
            }
            CoreLog.write("nway: rescue declined — word-shaped in \(langs.sorted().joined(separator: "/")), nothing to choose [\(dump)]")
            return nil
        }
    }

    /// Render of the typed keys in the CURRENT layout — what the word looks like on screen
    /// when nothing was converted. Used by the phrase tracker's bookkeeping.
    public func renderCurrent(keys: [TypedKey]) -> String? {
        rendered(keys, in: catalog.currentLayoutID())
    }

    /// Render of the typed keys in the layout with the given ID — used by phrase corrections
    /// to re-render defaulted words into the newly established language.
    public func render(keys: [TypedKey], layoutID: String) -> String? {
        rendered(keys, in: layoutID)
    }

    /// One step of the manual cycle: target layout + how the input looks in it.
    public struct ManualCandidate {
        public let targetLayoutID: String
        public let converted: String
    }

    /// Manual trigger plan: the original text (render in the current layout) + ordered
    /// candidates to cycle through. Unlike `resolve` (auto, precision-first, dictionary):
    /// this is an EXPLICIT user action, so we cycle through ALL layouts that give a different
    /// render, even without a dictionary and under ambiguity. An unambiguous dictionary winner
    /// is placed first. `nil` — if a render is impossible (no layout data; forwarded remote-desktop chars).
    public func manualPlan(keys: [TypedKey], capsLock: Bool, ambiguousLang: String)
        -> (original: String, originalLayoutID: String, candidates: [ManualCandidate])? {
        guard !keys.isEmpty else { return nil }
        // Chars forwarded through a remote desktop (keyCode 0 + char) render identically in
        // every layout — cycling over layouts is pointless. Let the caller handle it (2-way by script).
        if keys.contains(where: { $0.char != nil }) { return nil }

        let layouts = catalog.installedLayouts()
        let currentID = catalog.currentLayoutID()
        guard let currentLayout = layouts.first(where: { $0.id == currentID }),
              let original = rendered(keys, in: currentID) else {
            return nil
        }

        // Render the input in every installed layout (order as in the OS), starting from the
        // one after the current and wrapping around, so the "next" candidate is predictable.
        //
        // Dedup by text AND language, not by text alone. uk and ru spell every word built from
        // their shared letters identically, so a text-only key collapsed them into one entry and
        // made the second language unreachable — including when the collision was with the text
        // already on screen, where there was no surviving candidate to carry the other layout.
        // Keying on the language means same-language duplicates (two Russian variants) still
        // collapse, while uk/ru stay separate steps. Such a step changes the layout without
        // changing a visible character; that is the price of being able to reach it at all.
        let currentLang = String(currentLayout.lang.prefix(2))
        let ordered = rotate(layouts, startingAfter: currentID)
        var candidates: [ManualCandidate] = []
        var seen: Set<String> = [key(original, currentLang)]   // don't re-offer what's on screen
        for layout in ordered {
            guard layout.id != currentID, let rendered = rendered(keys, in: layout.id) else { continue }
            let k = key(rendered, String(layout.lang.prefix(2)))
            guard !seen.contains(k) else { continue }
            seen.insert(k)
            candidates.append(ManualCandidate(targetLayoutID: layout.id, converted: rendered))
        }
        guard !candidates.isEmpty else { return nil }

        // The dictionary winner (from the same punctuation-aware evaluation the auto path uses)
        // goes first, so one tap gives the "correct" layout in the typical case. Under uk/ru
        // ambiguity the preferred ambiguity language takes that spot instead — one ⌥ tap gives
        // the same answer auto-fix would.
        var promoted: (layoutID: String, converted: String)?
        // Unguarded: the precision guards restrain the app's own initiative, and the user pressing
        // the trigger is not that. A two-letter word still gets an answer.
        switch evaluate(keys: keys, capsLock: capsLock, phraseLang: nil, weighEvidence: false) {
        case .convert(let d), .rescued(let d):
            promoted = (d.targetLayoutID, d.converted)
        case .ambiguous(_, let winners):
            if ambiguousLang != "off", let w = winners.first(where: { $0.lang == ambiguousLang }) {
                promoted = (w.layoutID, w.converted)
            }
        case .keep, .held:
            break
        }
        // Match by rendered text, and carry the winner's LAYOUT — not just move its text to the
        // front. uk and ru render every word built from their shared letters identically, so the
        // dedup above keeps only whichever came first in rotation order and the winning layout is
        // usually NOT the survivor. Reordering alone therefore produced the right word in the wrong
        // layout: `хорошо` is Russian-only and used to leave the user typing Ukrainian, and the
        // ambiguity preference could never move anything at all. Rewriting the id fixes both, and
        // keeps the cycle one step long — an extra step showing identical text would read as the
        // trigger doing nothing. The text match IS the collapse signal: candidates are unique by
        // rendered string, so a winner absent by id but present by text was collapsed into it.
        if let promoted,
           let idx = candidates.firstIndex(where: { $0.converted == promoted.converted }) {
            candidates.remove(at: idx)
            candidates.insert(ManualCandidate(targetLayoutID: promoted.layoutID,
                                              converted: promoted.converted), at: 0)
        }

        CoreLog.write("manual: \(candidates.count) candidate(s): " +
                      candidates.map { "\($0.targetLayoutID.components(separatedBy: ".").last ?? "?")" }.joined(separator: "→"))
        return (original, currentID, candidates)
    }

    /// Dedup key: the same text in two different languages is two different candidates.
    private func key(_ text: String, _ lang: String) -> String { lang + "\u{0}" + text }

    /// The list of layouts rotated so it starts right AFTER the layout `afterID`.
    private func rotate(_ layouts: [Layout], startingAfter afterID: String) -> [Layout] {
        guard let i = layouts.firstIndex(where: { $0.id == afterID }) else { return layouts }
        return Array(layouts[(i + 1)...]) + Array(layouts[...i])
    }

    /// How the typed keycodes look in a specific layout. For text forwarded through a
    /// remote desktop (keyCode 0 + char) every layout would give the same character,
    /// so N-way doesn't apply there — return nil (handled by the old 2-way path).
    private func rendered(_ keys: [TypedKey], in layoutID: String) -> String? {
        if keys.contains(where: { $0.char != nil }) { return nil }
        return catalog.render(keys, layoutID: layoutID)
    }
}

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

    /// Full evaluation result. `.ambiguous` carries every validating language so the caller
    /// can resolve it by the preferred-language setting / phrase lock (phrase-aware-ambiguity);
    /// `resolve` collapses it to nil for callers that only care about the unambiguous case.
    public enum Outcome {
        case keep
        case convert(Decision)
        case ambiguous(original: String, winners: [Winner])
    }

    /// Legacy single-winner view of `evaluate` — nil unless exactly one language matches.
    public func resolve(keys: [TypedKey], capsLock: Bool) -> Decision? {
        if case .convert(let d) = evaluate(keys: keys, capsLock: capsLock) { return d }
        return nil
    }

    /// Renders the input through all layouts-with-dictionary and picks the target.
    /// `.keep` if: the layout/language can't be determined; the word is valid in the
    /// current language; no other language matches. `.ambiguous` when several do.
    public func evaluate(keys: [TypedKey], capsLock: Bool) -> Outcome {
        guard !keys.isEmpty else { return .keep }

        let layouts = catalog.installedLayouts()
        let currentID = catalog.currentLayoutID()
        guard let currentLayout = layouts.first(where: { $0.id == currentID }) else {
            CoreLog.write("nway: nil — current layout not resolvable (id=\(currentID.components(separatedBy: ".").last ?? "?"), installed=\(layouts.count))")
            return .keep
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
            return .keep
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
        if current.isValid {
            CoreLog.write("nway: nil — '\(current.string)' is a valid \(currentLang) word [\(dump)]")
            return .keep
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
            CoreLog.write("nway: nil — no valid target language [\(dump)]")
            return .keep
        }
        if winners.count > 1 {
            CoreLog.write("nway: ambiguous (\(winners.map(\.lang).sorted().joined(separator: "/"))) [\(dump)]")
            return .ambiguous(original: current.string, winners: winners)
        }
        let winner = winners[0]
        return .convert(Decision(targetLayoutID: winner.layoutID, lang: winner.lang,
                                 original: current.string, converted: winner.converted))
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
        guard layouts.contains(where: { $0.id == currentID }),
              let original = rendered(keys, in: currentID) else {
            return nil
        }

        // Render the input in every installed layout (order as in the OS), starting from the
        // one after the current and wrapping around, so the "next" candidate is predictable.
        let ordered = rotate(layouts, startingAfter: currentID)
        var candidates: [ManualCandidate] = []
        var seen: Set<String> = [original]   // don't offer what's already on screen, nor duplicates
        for layout in ordered {
            guard layout.id != currentID, let rendered = rendered(keys, in: layout.id) else { continue }
            guard !seen.contains(rendered) else { continue }
            seen.insert(rendered)
            candidates.append(ManualCandidate(targetLayoutID: layout.id, converted: rendered))
        }
        guard !candidates.isEmpty else { return nil }

        // The dictionary winner (from the same punctuation-aware evaluation the auto path uses)
        // goes first, so one tap gives the "correct" layout in the typical case. Under uk/ru
        // ambiguity the preferred ambiguity language takes that spot instead — one ⌥ tap gives
        // the same answer auto-fix would. Match by layout ID, falling back to the rendered
        // string in case the winner's layout was collapsed during dedup (identical render).
        var promoted: (layoutID: String, converted: String)?
        switch evaluate(keys: keys, capsLock: capsLock) {
        case .convert(let d):
            promoted = (d.targetLayoutID, d.converted)
        case .ambiguous(_, let winners):
            if ambiguousLang != "off", let w = winners.first(where: { $0.lang == ambiguousLang }) {
                promoted = (w.layoutID, w.converted)
            }
        case .keep:
            break
        }
        if let promoted,
           let idx = candidates.firstIndex(where: { $0.targetLayoutID == promoted.layoutID })
                  ?? candidates.firstIndex(where: { $0.converted == promoted.converted }) {
            let w = candidates.remove(at: idx)
            candidates.insert(w, at: 0)
        }

        CoreLog.write("manual: \(candidates.count) candidate(s): " +
                      candidates.map { "\($0.targetLayoutID.components(separatedBy: ".").last ?? "?")" }.joined(separator: "→"))
        return (original, currentID, candidates)
    }

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

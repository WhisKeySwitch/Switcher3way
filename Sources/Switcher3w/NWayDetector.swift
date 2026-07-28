import AppKit
import Carbon

/// N-way layout detection: generalizes `LayoutDetector.decide` from a pair to any number
/// of installed layouts (e.g. EN + UK + RU). The typed keycodes are rendered through
/// EVERY layout that has a system dictionary, and the word is validated in that layout's
/// language. Precision-first: switch only when there is exactly one target language.
enum NWayResolver {

    /// One candidate: layout + its language + how the input looks in it + whether the word is valid.
    private struct Candidate {
        let layoutID: String
        let lang: String      // 2-letter code (ru/uk/en…)
        let string: String    // keycodes read in this layout
        let isValid: Bool     // string is a real word in the language dictionary
    }

    /// Decision: which layout to switch to and what text to type. nil — leave as is.
    struct Decision {
        let targetLayoutID: String
        let lang: String      // 2-letter code of the target language
        let original: String
        let converted: String
    }

    /// One language that validates the typed word (returned when more than one does).
    struct Winner {
        let lang: String
        let layoutID: String
        let converted: String
    }

    /// Full evaluation result. `.ambiguous` carries every validating language so the caller
    /// can resolve it by the preferred-language setting / phrase lock (phrase-aware-ambiguity);
    /// `resolve` collapses it to nil for callers that only care about the unambiguous case.
    enum Outcome {
        case keep
        case convert(Decision)
        case ambiguous(original: String, winners: [Winner])
    }

    /// Legacy single-winner view of `evaluate` — nil unless exactly one language matches.
    @MainActor
    static func resolve(keys: [TypedKey], capsLock: Bool) -> Decision? {
        if case .convert(let d) = evaluate(keys: keys, capsLock: capsLock) { return d }
        return nil
    }

    /// Renders the input through all layouts-with-dictionary and picks the target.
    /// `.keep` if: the layout/language can't be determined; the word is valid in the
    /// current language; no other language matches. `.ambiguous` when several do.
    @MainActor
    static func evaluate(keys: [TypedKey], capsLock: Bool) -> Outcome {
        guard !keys.isEmpty else { return .keep }

        let layouts = LayoutSwitcher.installedLayouts()
        let currentID = LayoutSwitcher.currentLayoutID()
        guard let currentSource = layouts.first(where: { LayoutSwitcher.sourceID($0) == currentID }),
              let currentLangFull = LayoutSwitcher.languageCode(currentSource) else {
            rslog("nway: nil — current layout not resolvable (id=\(currentID.components(separatedBy: ".").last ?? "?"), installed=\(layouts.count))")
            return .keep
        }
        let currentLang = String(currentLangFull.prefix(2))

        // One candidate per language (several layouts of the same language — e.g. US/ABC — are
        // collapsed, preferring the valid and canonical one). Skip languages without a system dictionary.
        // Validity is judged on the letter "core" — edge punctuation/digits stripped — so that a
        // trailing "!" or a leading "(" doesn't hide an otherwise-valid word.
        var byLang: [String: Candidate] = [:]
        for layout in layouts {
            guard let langFull = LayoutSwitcher.languageCode(layout) else { continue }
            let lang = String(langFull.prefix(2))
            guard Dict.isAvailable(lang) else { continue }
            guard let rendered = render(keys, layout: layout) else { continue }
            let valid = Dict.isValidWord(letterCore(Array(rendered)).lowercased(), lang: lang)
            let id = LayoutSwitcher.sourceID(layout)
            if let existing = byLang[lang] {
                if valid && !existing.isValid {   // a valid render outweighs any other
                    byLang[lang] = Candidate(layoutID: id, lang: lang, string: rendered, isValid: true)
                }
            } else {
                byLang[lang] = Candidate(layoutID: id, lang: lang, string: rendered, isValid: valid)
            }
        }

        // Compact candidate dump for diagnosing "keep" decisions (only built when debug log is on).
        let dump = byLang.values
            .sorted { $0.lang < $1.lang }
            .map { "\($0.lang):'\($0.string)'\($0.isValid ? " VALID" : "")" }
            .joined(separator: " ")

        guard let current = byLang[currentLang] else {
            rslog("nway: nil — no candidate for current lang \(currentLang) [\(dump)]")
            return .keep
        }
        // always-convert — an EXPLICIT user override: if some other language's letter core is in
        // the "always convert" list, switch there even bypassing the dictionary and vetoes.
        for cand in byLang.values where cand.lang != currentLang {
            if AutoSwitchPolicy.isAlwaysConvert(letterCore(Array(cand.string))) {
                return .convert(Decision(targetLayoutID: cand.layoutID, lang: cand.lang,
                                         original: current.string, converted: cand.string))
            }
        }

        // Typed correctly in the current language (its letter core is a real word) → do nothing.
        if current.isValid {
            rslog("nway: nil — '\(current.string)' is a valid \(currentLang) word [\(dump)]")
            return .keep
        }

        // Other languages where the input's letter core is a real word. Only the LETTER core is
        // validated (edge punctuation/digits trimmed), but the whole token is re-rendered in the
        // target layout on output — punctuation keys convert too (the "/" key is "." on the RU/UK
        // PC layouts, the "," key is "б", etc.), because the keystrokes were meant for that layout.
        var winners: [Winner] = []
        for cand in byLang.values where cand.lang != currentLang {
            let core = letterCore(Array(cand.string))
            guard LayoutDetector.passesSoftGates(core, capsLock: capsLock) else { continue }
            guard Dict.isValidWord(core.lowercased(), lang: cand.lang) else { continue }
            winners.append(Winner(lang: cand.lang, layoutID: cand.layoutID, converted: cand.string))
        }
        // 0 — not wrong-layout. >1 — ambiguous (uk↔ru): reported as such so the caller can
        // apply the preferred-language / phrase-lock policy (phrase-aware-ambiguity).
        if winners.isEmpty {
            rslog("nway: nil — no valid target language [\(dump)]")
            return .keep
        }
        if winners.count > 1 {
            rslog("nway: ambiguous (\(winners.map(\.lang).sorted().joined(separator: "/"))) [\(dump)]")
            return .ambiguous(original: current.string, winners: winners)
        }
        let winner = winners[0]
        return .convert(Decision(targetLayoutID: winner.layoutID, lang: winner.lang,
                                 original: current.string, converted: winner.converted))
    }

    /// Render of the typed keys in the CURRENT layout — what the word looks like on screen
    /// when nothing was converted. Used by the phrase tracker's bookkeeping.
    @MainActor
    static func renderCurrent(keys: [TypedKey]) -> String? {
        let layouts = LayoutSwitcher.installedLayouts()
        let currentID = LayoutSwitcher.currentLayoutID()
        guard let current = layouts.first(where: { LayoutSwitcher.sourceID($0) == currentID }) else { return nil }
        return render(keys, layout: current)
    }

    /// Render of the typed keys in the layout with the given ID — used by phrase corrections
    /// to re-render defaulted words into the newly established language.
    @MainActor
    static func render(keys: [TypedKey], layoutID: String) -> String? {
        guard let layout = LayoutSwitcher.installedLayouts()
            .first(where: { LayoutSwitcher.sourceID($0) == layoutID }) else { return nil }
        return render(keys, layout: layout)
    }

    /// The contiguous range of `chars` with leading/trailing characters that satisfy `drop` removed.
    private static func coreRange(count: Int, drop: (Int) -> Bool) -> Range<Int> {
        var lo = 0, hi = count
        while lo < hi && drop(lo) { lo += 1 }
        while hi > lo && drop(hi - 1) { hi -= 1 }
        return lo..<hi
    }

    /// The word's letter core: the render with leading/trailing non-letters trimmed.
    private static func letterCore(_ chars: [Character]) -> String {
        String(chars[coreRange(count: chars.count) { !chars[$0].isLetter }])
    }

    /// One step of the manual cycle: target layout + how the input looks in it.
    struct ManualCandidate {
        let targetLayoutID: String
        let converted: String
    }

    /// Manual trigger plan: the original text (render in the current layout) + ordered
    /// candidates to cycle through. Unlike `resolve` (auto, precision-first, dictionary):
    /// this is an EXPLICIT user action, so we cycle through ALL layouts that give a different
    /// render, even without a dictionary and under ambiguity. An unambiguous dictionary winner
    /// is placed first. `nil` — if a render is impossible (no layout data; forwarded remote-desktop chars).
    @MainActor
    static func manualPlan(keys: [TypedKey], capsLock: Bool)
        -> (original: String, originalLayoutID: String, candidates: [ManualCandidate])? {
        guard !keys.isEmpty else { return nil }
        // Chars forwarded through a remote desktop (keyCode 0 + char) render identically in
        // every layout — cycling over layouts is pointless. Let the caller handle it (2-way by script).
        if keys.contains(where: { $0.char != nil }) { return nil }

        let layouts = LayoutSwitcher.installedLayouts()
        let currentID = LayoutSwitcher.currentLayoutID()
        guard let currentSource = layouts.first(where: { LayoutSwitcher.sourceID($0) == currentID }),
              let original = render(keys, layout: currentSource) else {
            return nil
        }

        // Render the input in every installed layout (order as in the OS), starting from the
        // one after the current and wrapping around, so the "next" candidate is predictable.
        let ordered = rotate(layouts, startingAfter: currentID)
        var candidates: [ManualCandidate] = []
        var seen: Set<String> = [original]   // don't offer what's already on screen, nor duplicates
        for layout in ordered {
            let id = LayoutSwitcher.sourceID(layout)
            guard id != currentID, let rendered = render(keys, layout: layout) else { continue }
            guard !seen.contains(rendered) else { continue }
            seen.insert(rendered)
            candidates.append(ManualCandidate(targetLayoutID: id, converted: rendered))
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
            let pref = SettingsManager.shared.ambiguousLang
            if pref != "off", let w = winners.first(where: { $0.lang == pref }) {
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

        rslog("manual: \(candidates.count) candidate(s): " +
              candidates.map { "\($0.targetLayoutID.components(separatedBy: ".").last ?? "?")" }.joined(separator: "→"))
        return (original, currentID, candidates)
    }

    /// The list of layouts rotated so it starts right AFTER the layout `afterID`.
    private static func rotate(_ layouts: [TISInputSource], startingAfter afterID: String) -> [TISInputSource] {
        guard let i = layouts.firstIndex(where: { LayoutSwitcher.sourceID($0) == afterID }) else {
            return layouts
        }
        return Array(layouts[(i + 1)...]) + Array(layouts[...i])
    }

    /// How the typed keycodes look in a specific layout. For text forwarded through a
    /// remote desktop (keyCode 0 + char) every layout would give the same character,
    /// so N-way doesn't apply there — return nil (handled by the old 2-way path).
    @MainActor
    private static func render(_ keys: [TypedKey], layout: TISInputSource) -> String? {
        if keys.contains(where: { $0.char != nil }) { return nil }
        guard let data = DynamicKeyMapping.layoutDataForSource(layout) else { return nil }
        var out = ""
        for k in keys {
            guard let c = DynamicKeyMapping.translateKeycode(k.keyCode, layoutData: data,
                                                             shift: k.shift, caps: k.caps) else {
                return nil
            }
            out.append(c)
        }
        return out
    }
}

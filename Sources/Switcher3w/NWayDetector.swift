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
        let original: String
        let converted: String
    }

    /// Renders the input through all layouts-with-dictionary and picks the target.
    /// Returns nil if: the layout/language can't be determined; the word is valid in the
    /// current language; there are zero OR more than one matching other languages
    /// (uk/ru ambiguity → leave it alone).
    @MainActor
    static func resolve(keys: [TypedKey], capsLock: Bool) -> Decision? {
        guard !keys.isEmpty else { return nil }

        let layouts = LayoutSwitcher.installedLayouts()
        let currentID = LayoutSwitcher.currentLayoutID()
        guard let currentSource = layouts.first(where: { LayoutSwitcher.sourceID($0) == currentID }),
              let currentLangFull = LayoutSwitcher.languageCode(currentSource) else {
            rslog("nway: nil — current layout not resolvable (id=\(currentID.components(separatedBy: ".").last ?? "?"), installed=\(layouts.count))")
            return nil
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
            return nil
        }
        // always-convert — an EXPLICIT user override: if some other language's letter core is in
        // the "always convert" list, switch there even bypassing the dictionary and vetoes.
        for cand in byLang.values where cand.lang != currentLang {
            if AutoSwitchPolicy.isAlwaysConvert(letterCore(Array(cand.string))) {
                return Decision(targetLayoutID: cand.layoutID, original: current.string, converted: cand.string)
            }
        }

        // Typed correctly in the current language (its letter core is a real word) → do nothing.
        if current.isValid {
            rslog("nway: nil — '\(current.string)' is a valid \(currentLang) word [\(dump)]")
            return nil
        }

        // Other languages where the input's letter core is a real word. Only the LETTER core is
        // validated (edge punctuation/digits trimmed), but the whole token is re-rendered in the
        // target layout on output — punctuation keys convert too (the "/" key is "." on the RU/UK
        // PC layouts, the "," key is "б", etc.), because the keystrokes were meant for that layout.
        var winners: [(layoutID: String, converted: String)] = []
        for cand in byLang.values where cand.lang != currentLang {
            let core = letterCore(Array(cand.string))
            guard LayoutDetector.passesSoftGates(core, capsLock: capsLock) else { continue }
            guard Dict.isValidWord(core.lowercased(), lang: cand.lang) else { continue }
            winners.append((cand.layoutID, cand.string))
        }
        // 0 — not wrong-layout; >1 — ambiguous (uk↔ru): precision-first, leave it alone.
        guard winners.count == 1, let winner = winners.first else {
            rslog("nway: nil — \(winners.isEmpty ? "no valid target language" : "ambiguous") [\(dump)]")
            return nil
        }

        return Decision(targetLayoutID: winner.layoutID, original: current.string, converted: winner.converted)
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

        // The unambiguous dictionary winner (from the same punctuation-aware `resolve` the auto path
        // uses — letter-core validation, edge punctuation trimmed) goes first, so one tap gives the
        // "correct" layout in the typical case. Match by layout ID, falling back to the rendered
        // string in case the winner's layout was collapsed during dedup (identical render).
        if let winner = resolve(keys: keys, capsLock: capsLock),
           let idx = candidates.firstIndex(where: { $0.targetLayoutID == winner.targetLayoutID })
                  ?? candidates.firstIndex(where: { $0.converted == winner.converted }) {
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

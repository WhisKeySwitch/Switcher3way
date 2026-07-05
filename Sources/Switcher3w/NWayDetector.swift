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
            return nil
        }
        let currentLang = String(currentLangFull.prefix(2))

        // One candidate per language (several layouts of the same language — e.g. US/ABC — are
        // collapsed, preferring the valid and canonical one). Skip languages without a system dictionary.
        var byLang: [String: Candidate] = [:]
        for layout in layouts {
            guard let langFull = LayoutSwitcher.languageCode(layout) else { continue }
            let lang = String(langFull.prefix(2))
            guard Dict.isAvailable(lang) else { continue }
            guard let rendered = render(keys, layout: layout) else { continue }
            let valid = Dict.isValidWord(rendered.lowercased(), lang: lang)
            let id = LayoutSwitcher.sourceID(layout)
            if let existing = byLang[lang] {
                if valid && !existing.isValid {   // a valid render outweighs any other
                    byLang[lang] = Candidate(layoutID: id, lang: lang, string: rendered, isValid: true)
                }
            } else {
                byLang[lang] = Candidate(layoutID: id, lang: lang, string: rendered, isValid: valid)
            }
        }

        guard let current = byLang[currentLang] else { return nil }
        let typed = current.string

        // always-convert — an EXPLICIT user override: if the render in some other language
        // is in the "always convert" list, switch there even bypassing the dictionary and vetoes.
        for cand in byLang.values where cand.lang != currentLang {
            if AutoSwitchPolicy.isAlwaysConvert(cand.string) {
                return Decision(targetLayoutID: cand.layoutID, original: typed, converted: cand.string)
            }
        }

        // Soft vetoes — the same as in 2-way (short/acronym/code/digits).
        guard LayoutDetector.passesSoftGates(typed, capsLock: capsLock) else { return nil }

        // Typed correctly in the current language → do nothing.
        if current.isValid { return nil }

        // Other languages where the input is a real word.
        let validOthers = byLang.values.filter { $0.lang != currentLang && $0.isValid }
        // 0 — not wrong-layout; >1 — ambiguous (uk↔ru): precision-first, leave it alone.
        guard validOthers.count == 1, let winner = validOthers.first else { return nil }

        return Decision(targetLayoutID: winner.layoutID, original: typed, converted: winner.string)
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

        // The unambiguous dictionary winner (as in auto) goes first, so one tap gives the
        // "correct" layout in the typical case.
        if let winner = resolve(keys: keys, capsLock: capsLock),
           let idx = candidates.firstIndex(where: { $0.targetLayoutID == winner.targetLayoutID }) {
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

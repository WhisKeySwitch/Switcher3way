import AppKit
import Carbon

/// N-way детект раскладки: обобщение `LayoutDetector.decide` с пары на любое число
/// установленных раскладок (напр. EN + UK + RU). Набранные keycodes прогоняются через
/// КАЖДУЮ раскладку, у которой есть системный словарь, и слово проверяется в языке этой
/// раскладки. Точность-first: переключаем, только когда целевой язык ровно один.
enum NWayResolver {

    /// Один кандидат: раскладка + её язык + как в ней выглядит набранное + валидно ли это слово.
    private struct Candidate {
        let layoutID: String
        let lang: String      // 2-буквенный код (ru/uk/en…)
        let string: String    // keycodes, прочитанные в этой раскладке
        let isValid: Bool     // string — реальное слово в language словаре
    }

    /// Решение: в какую раскладку переключиться и какой текст впечатать. nil — оставить как есть.
    struct Decision {
        let targetLayoutID: String
        let original: String
        let converted: String
    }

    /// Прогоняет набранное через все раскладки-с-словарём и выбирает целевую.
    /// Возвращает nil, если: раскладку/язык не определить; слово валидно в текущем языке;
    /// подходящих других языков ноль ИЛИ больше одного (неоднозначность uk/ru → не трогаем).
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

        // Один кандидат на язык (несколько раскладок одного языка — напр. US/ABC — схлопываем,
        // предпочитая валидную и каноничную). Пропускаем языки без системного словаря.
        var byLang: [String: Candidate] = [:]
        for layout in layouts {
            guard let langFull = LayoutSwitcher.languageCode(layout) else { continue }
            let lang = String(langFull.prefix(2))
            guard Dict.isAvailable(lang) else { continue }
            guard let rendered = render(keys, layout: layout) else { continue }
            let valid = Dict.isValidWord(rendered.lowercased(), lang: lang)
            let id = LayoutSwitcher.sourceID(layout)
            if let existing = byLang[lang] {
                if valid && !existing.isValid {   // валидный рендер важнее любого другого
                    byLang[lang] = Candidate(layoutID: id, lang: lang, string: rendered, isValid: true)
                }
            } else {
                byLang[lang] = Candidate(layoutID: id, lang: lang, string: rendered, isValid: valid)
            }
        }

        guard let current = byLang[currentLang] else { return nil }
        let typed = current.string

        // always-convert — ЯВНЫЙ override пользователя: если рендер в каком-то другом языке
        // лежит в списке «всегда конвертить», переключаем туда даже минуя словарь и вето.
        for cand in byLang.values where cand.lang != currentLang {
            if AutoSwitchPolicy.isAlwaysConvert(cand.string) {
                return Decision(targetLayoutID: cand.layoutID, original: typed, converted: cand.string)
            }
        }

        // Мягкие вето — те же, что в 2-way (короткое/акроним/код/цифры).
        guard LayoutDetector.passesSoftGates(typed, capsLock: capsLock) else { return nil }

        // Набрано корректно в текущем языке → ничего не делаем.
        if current.isValid { return nil }

        // Другие языки, где набранное — реальное слово.
        let validOthers = byLang.values.filter { $0.lang != currentLang && $0.isValid }
        // 0 — не wrong-layout; >1 — неоднозначно (uk↔ru): точность-first, не трогаем.
        guard validOthers.count == 1, let winner = validOthers.first else { return nil }

        return Decision(targetLayoutID: winner.layoutID, original: typed, converted: winner.string)
    }

    /// Как набранные keycodes выглядят в конкретной раскладке. Для проброшенного через
    /// удалённый стол текста (keyCode 0 + char) все раскладки дали бы один и тот же символ,
    /// поэтому N-way там неприменим — возвращаем nil (обрабатывается старым 2-way путём).
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

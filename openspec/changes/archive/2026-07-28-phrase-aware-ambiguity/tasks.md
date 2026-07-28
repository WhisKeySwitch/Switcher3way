## 1. Resolver: expose ambiguity

- [x] 1.1 Add `NWayResolver.Outcome` (`.keep` / `.convert(Decision)` / `.ambiguous([Winner])`, `Winner = (lang, layoutID, converted)`) and `evaluate(keys:capsLock:)`; turn `resolve` into a wrapper returning `Decision?` for `.convert` only
- [x] 1.2 `manualPlan`: when `resolve` gives no winner because of ambiguity, promote the preferred-language candidate to the front of the cycle

## 2. Settings + UI

- [x] 2.1 `SettingsManager`: `ambiguousLang` property over `com.switcher3w.ambiguousLang` ("uk" default / "ru" / "off"), read live
- [x] 2.2 Auto-fix tab: popup row «Мова для неоднозначних слів» (Українська / Русский / localized "Do not convert") via the FormBox factories
- [x] 2.3 `Localization.swift`: label + "do not convert" strings for en/uk/ru (others fall back to English)

## 3. PhraseTracker

- [x] 3.1 New `Sources/Switcher3w/PhraseTracker.swift`: `PhraseWord` (keys, shownText, spacesAfter, kind: defaulted/locked/neutral), lock state, `record`, `noteExtraSpace`, `reset`, contradiction detection
- [x] 3.2 `correction(toLang:layoutID:)`: segment from the first defaulted-to-other-language word through the last word — defaulted words re-rendered via `DynamicKeyMapping`, neutral/locked words verbatim, spaces from `spacesAfter`; returns `(oldSegment, newSegment, eraseCount)`; nil if contradictory, nothing defaulted, or eraseCount > 200
- [x] 3.3 `KeyboardMonitor` hooks: phrase-reset callback from `fullReset`/`resetBuffersOnClick`, extra-space callback from the boundary branch (`boundaryCount += 1` path)

## 4. Orchestration in handleAutoConvert

- [x] 4.1 Switch to `evaluate`; on `.ambiguous` pick phrase lock → setting → keep; convert the single word and record it as `defaulted` on retype success
- [x] 4.2 On `.convert` with pending defaulted words of another language (no conflicting lock): build the combined segment (correction + current word) and run it as one `beginCycle`; on success switch layout, re-mark corrected words as locked, record the current word
- [x] 4.3 Record neutral words (`.keep` and valid-in-current outcomes) with their on-screen render; reset the tracker on retype abort, focus-change bail, secure-input bail, and app deactivation
- [x] 4.4 Verify the ⌥-undo cycle restores a phrase correction as one step (home = old segment) and `offerExceptionAfterUndo` still behaves

## 5. Docs

- [x] 5.1 Update `docs/user-guide.md`, `.uk.md`, `.ru.md`: ambiguity default, phrase correction, the new Auto-fix setting (compiled into in-app help by the build)

## 6. Build and verify

- [x] 6.1 `swift build` clean; `bash build_app.sh`, install, relaunch, permissions line OK
- [x] 6.2 Type «Lj,ht? oj ' ghjuhtc» («Добре, що є прогрес») in EN layout with pauses — «добре» now converts to uk immediately; whole phrase correct
- [x] 6.3 Type an ambiguous word then a ru-only word (e.g. «привет») in EN layout — the defaulted word re-converts to ru together with the trigger word, layout ends on ru
- [x] 6.4 Contradiction test: uk-only word then ru-only word — only the current word converts, no retroaction
- [x] 6.5 Setting «off» → ambiguous words keep (old behavior); setting «ru» → ambiguous words default to ru
- [x] 6.6 ⌥ after a phrase correction undoes the whole segment and restores the layout; Enter/click resets the phrase (no cross-line corrections)

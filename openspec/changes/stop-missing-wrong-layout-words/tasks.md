## 1. Resolver rules that need no app change (macOS core)

- [x] 1.1 `NWayResolver.evaluate`: consult `TypoGuard.nearMiss` only when `coreLength >= nearMissTrustedFrom` (design D1); update the comment above the call to say the band explicitly.
- [x] 1.2 `NWayResolver.evaluate`: candidate validity is `!core.isEmpty && dict.isValidWord(...)`; an all-non-letter token reaches `.keep(.notAWordAnywhere)` with the existing "no valid target language" log line (D3).
- [x] 1.3 `SoftGates.passes`: allow `'`, `’`, `-` when internal; keep all other non-letters rejected; all-caps / camelCase / mixed-script judged on letters only (D6).
- [x] 1.4 `NWayResolver.evaluate`: when the single winner's letter core equals the typed core case-insensitively, skip the typo guard and return `.convert` with `original == converted`; add `Decision.isLayoutOnly` and a log line `nway: same text, layout only → <lang>` (D2).
- [x] 1.5 Tests in `Tests/Switcher3wCoreTests`: five-letter wrong-layout word with a one-edit neighbour converts (Дякую/`Lzre` shape); six-letter one still keeps as `.looksLikeATypo`; `10`, `.`, `))` are `.notAWordAnywhere`; `you're` / `кто-то` convert; `слишком` typed on uk yields a layout-only decision to ru; `it@x.io`-style core still fails the gates. Run `swift test`.

## 2. Phrase lock and ambiguity (macOS app)

- [x] 2.1 `AppDelegate.handleAutoConvert`: on `.keep(.validInCurrent)`, set `keepKind = .locked` only when the letter core is at least `NWayResolver.undecidableBelow` letters; otherwise `.neutral` (D4).
- [x] 2.2 `AppDelegate.handleAutoConvert` `.ambiguous` branch: use the phrase lock only if it is one of the winners, else the preference; log `(phrase lock)` / `(preference)` / `(preference; lock <lang> not a candidate)` (D5).
- [x] 2.3 `PhraseTrackerTests` / `EvaluateTests`: a two-letter current-language word does not lock; a four-letter one does; an ambiguous uk/ru word under an en lock resolves to the preference. (Lock logic lives in the app, so assert the resolver side and add a small pure helper for the length rule if needed to make it testable.)

## 3. Same-text layout-only apply (macOS app)

- [x] 3.1 `AppDelegate.handleAutoConvert`: if `decision.isLayoutOnly` and no phrase correction is pending, skip `beginCycle`; call `LayoutSwitcher.switchTo`, `keyboardMonitor.markConverted()` is NOT called (nothing was rewritten), record the word `.locked(lang)`, `updateStatusIcon()`, log `auto: layout only → <layoutID>` (D2).
- [x] 3.2 If a phrase correction IS pending on a layout-only decision, run the existing correction retype (earlier defaulted words change text) with `home`/`insert` built as today — the current word's text is identical on both sides.
- [x] 3.3 `CaretIndicator.conversionApplied`: when original equals converted, show a "layout switched" form (target language badge, no strikethrough) instead of identical text struck through.
- [ ] 3.4 (needs a live session — not done here) Manual check with the debug log: type a Russian word on the Ukrainian layout, confirm the layout flips, text untouched, chip shows the layout form, `⌥` afterwards still cycles.

## 4. Vowel-less held word (macOS, measured)

- [x] 4.1 `WordShape.hasVowel(_:vowels:)` (public, pure); `handleHeldWord` settles immediately when `winners.count == 1` and the typed core has no vowel of the current language and the vowel set is non-empty; log `auto: held word has no vowel in <lang>, settling → <lang>` (D7).
- [x] 4.2 `VowelLessFixture.swift` with the D7 token list per language, typed as themselves; `VowelLessHeldWordTests` evaluates each with the REAL `SystemDictionary` (like `DictionaryQualityTests`, `#if canImport(AppKit)`) and asserts the rule converts none; plus fake-dictionary cases for `щт`→on, `тщ`→no, `nfr`→так settling and `туц`→new (has a vowel) still waiting.
- [x] 4.3 If 4.2 cannot reach zero, disable the rule (short-circuit `hasVowel` to true in the app call site), keep the test reporting the count, and record the offending tokens here.
  **Measured 2026-09-08 (real NSSpellChecker, 76 tokens): 18/76 would convert.** 11 were same-text uk→ru flips (хз пн вт чт пт сб др мб тчк тк — the ru dictionary lists them, uk does not); excluding same-text winners leaves **8/76**: смс→cvc, тг→nu, мс→vc (from both uk and ru), dst→вые, tl→ед. Not zero → rule shipped OFF behind `NWayResolver.vowelLessHeldWordEnabled = false`; `heldWordSettlesAlone` carries the predicate, `VowelLessHeldWordMeasurement` prints the count every run and fails if the fixture ever measures clean while the switch is still off.

## 5. Windows core and app parity

- [x] 5.1 `NWayResolver.cs`: 1.1, 1.2, 1.4 with the same constants and a `Decision.IsLayoutOnly` property.
- [x] 5.2 `SoftGates.cs` `PassesSoftGates`: 1.3.
- [x] 5.3 `Engine.cs`: lock only from `UndecidableBelow` letters (2.1); ambiguity lock-outside-candidates fallback (2.2); layout-only apply without `TextRewriter` (3.1/3.2); `CaretChip` layout-switched form (3.3); vowel-less held settlement (4.1) behind the fixture.
- [x] 5.4 `windows/tests/Switcher3way.Core.Tests`: twin of every Swift case in 1.5, 2.3, 4.2 (Hunspell dictionaries, so the vowel-less fixture measures for real here too).
- [x] 5.5 Re-run `TypingSimulationTests`; record typo-conversion rate and wrong-layout recall before/after in this file. Gate: typo conversion stays 0%.
  **Measured (baseline `main` → after), Windows core suite, real Hunspell:** paragraph simulation 0 mangled / 0 layout switches → **0 / 0** (gate holds); short typos 0/403 → **0/403**; recall uk-in-en 51.7% → **57.5%**, en-in-uk 51.8% → **69.9%**; per-word typo precision uk 0/1399 → **1/1399** (друкую→рукую→`here.`), en 0/1049 → **1/1049** (fine→ifne→`шату`) — the documented cost of the 4–5 letter band. Two refinements came out of this run and are in the design as D2 (same-text needs phrase corroboration; unconditional it flipped 15/1399 uk typos to ru) and D2b (band judged on the shorter core; fixed рухх→`he[[`). Both suites green: Swift 110, Windows 206.

## 7. Short-word allow-list (the reported defect: це kept as wt)

- [x] 7.1 `Sources/Switcher3wCore/ShortWords.swift`: `admits(core, lang)` consulted below four letters, curated en/uk/ru lists, fail open for an unlisted language (design D9).
- [x] 7.2 `NWayResolver.evaluate`: AND `ShortWords.admits` into candidate validity, in the one place validity is computed, so it covers the typed side and the candidates alike.
- [x] 7.3 `ShortWordsTests`: the noise (`wt`, `ye`, `pf`, `lys`) not admitted; real words and daily abbreviations admitted; ignored from four letters up; unlisted language falls through; and end to end, `wt` no longer keeps and converts to `це` inside a Ukrainian phrase.
- [x] 7.4 `ShortWordFixture` + `ShortWordPrecisionTests`: the short words of the prose corpus must all be admitted (coverage reported, fails below 100%), the noise must stay out, and two cases prove the defect fixed against the REAL system dictionary while all 50 real English short words survive inside a Ukrainian phrase.
- [x] 7.5 Windows: `ShortWords.cs` generated from the Swift file (single source of the data), wired into `NWayResolver.Evaluate` identically.
- [x] 7.6 Re-measure both ports; record below.
  **Measured 2026-09-09.** Windows corpus, unchanged by this addition: paragraph simulation 0 mangled / 0 layout switches, short typos 0/403, per-word typo precision uk 1/1399 and en 1/1049, recall 57.5% and 69.9%. Short-word list coverage over prose: en 100% (50/50), uk 100% (46/46), ru 100% (82/82). The coverage gate caught `так`, `там`, `нет`, `он` missing from Russian on its first run. Side effect: the vowel-less false conversions fell from 8/76 to 2/76 on macOS and 0/76 on Windows, because most were junk winners; the rule stays off since the bar is zero on both. Swift 123 tests, Windows 206, both green.

## 6. Docs and release

- [x] 6.1 `CLAUDE.md`: current-state bullet for 1.6.0 (what the log showed, what changed, the measured numbers); note the vowel-less rule's fixture gate and the `wt`/`ye`/`uk` dictionary residual under Known issues.
- [x] 6.2 `docs/user-guide*.md` (EN/UK/RU): one sentence under auto-fix that a word spelled the same in Ukrainian and Russian switches only the layout, and what the chip shows then.
- [x] 6.3 `openspec validate --specs` and `openspec validate --change stop-missing-wrong-layout-words`.
- [ ] 6.4 (version bumped to 1.6.0 build 44 and `Switcher3way.app` built and signed here; the install and the day of logging are yours) `version.json` → 1.6.0; `bash build_app.sh`; install; run with the debug log for a day and confirm the six log patterns from the 08-27..09-08 log no longer appear for real wrong-layout words.

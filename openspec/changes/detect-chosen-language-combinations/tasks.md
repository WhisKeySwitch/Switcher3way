# Tasks

## 1. Measure first

- [ ] 1.1 Replace the draft `BulgarianCostTests.swift` with `LanguageCombinationTests.swift`, which reads layout tables at run time from every installed input source and skips a language with a printed reason when its layout or dictionary is missing. Verify: the file compiles and the old draft is gone.
- [ ] 1.2 Add prose corpora for ru, bg, de and fr next to the Windows port's en and uk text, each at least 200 words of ordinary writing. Verify: the measurement prints a word count per language, and every word is typable on that language's default layout or counted as skipped.
- [ ] 1.3 Implement the four measurements per combination: keep, typos, recall and wrong-text conversions, with the en+uk+ru baseline taken in the same run. Verify: `SWITCHER3W_MEASURE_COMBINATIONS=1 swift test --filter LanguageCombinationTests` prints one line per combination and per measurement.
- [ ] 1.4 Run the measurement before any code change and record the numbers in this file as the "before" table. Verify: the table lists all 35 combinations of {en, uk, ru, bg, de, fr} plus the Bulgarian Phonetic variant.

## 2. Core: language profiles

- [ ] 2.1 Add `LanguageProfile` to `Switcher3wCore` with script, vowels, canary and admitted flag for en, uk, ru, and unadmitted rows for bg, de, fr. Verify: a unit test asserts every admitted profile has vowels, a canary and a short-word list.
- [ ] 2.2 Route `SystemDictionary.vowels` and the sentinel canaries through the table. Verify: the full `swift test` suite passes unchanged.
- [ ] 2.3 Skip unadmitted languages when building candidates, and keep a word typed in one with reason `unsupportedLanguage`; leave `manualPlan` alone. Verify: tests show a German layout is ignored while unadmitted, still appears in the manual plan, and typing on it keeps with that reason.
- [ ] 2.4 Log once per language per session that a language was skipped. Verify: a test through `CoreLog` sees one line for repeated evaluations.

## 3. Core: transliterating layouts

- [ ] 3.1 Add a `transliterates` flag to `Layout`, defaulting to false. Verify: existing tests compile and pass.
- [ ] 3.2 In `evaluate`, do not make a flagged layout a candidate unless it is current or its language is ru or uk, and prefer a standard layout of the same language. Verify: fake-catalog tests cover an English typo with Bulgarian Phonetic enabled, typing on Bulgarian Phonetic as the current layout, both Bulgarian layouts enabled, and Russian Phonetic unchanged.
- [ ] 3.3 Detect the flag in `SystemLayoutCatalog` from the `a e i o u` keys for non-Latin languages. Verify: a test reading the real layouts flags Bulgarian Phonetic, Russian Phonetic and Ukrainian QWERTY, and does not flag Ukrainian-PC, RussianWin, Bulgarian, German or French.

## 4. Core: ties

- [ ] 4.1 Change the rescue's tie rule from the uk/ru pair to "all plausible candidates share a script", resolved through `resolveAmbiguity`. Verify: tests cover a uk/bg rescue tie resolving to the preference, a bg/ru tie with a uk preference keeping, a cross-script tie keeping, and the existing uk/ru rescue tests still passing.
- [ ] 4.2 Make the log line for an unresolved tie name the tied languages and the preference. Verify: a test asserts the reason text for the bg/ru tie with a uk preference.

## 5. Per-language knowledge for bg, de, fr

- [ ] 5.1 Write Bulgarian, German and French short-word lists in `ShortWords.swift`, and add their prose short words to `ShortWordFixture.inProse`. Verify: `ShortWordPrecisionTests` reports 100% coverage for all six languages.
- [ ] 5.2 Add vowels and canaries for bg, de and fr, checking each canary against the real spell checker. Verify: a test asserts each canary word is accepted and each mash rejected on this Mac.
- [ ] 5.3 Run the measurement with the new knowledge and set `admitted` for each language that passes every combination. Record the "after" table and each admission or decline with its reason in this file. Verify: the gated run passes, and any declined language has its failing combinations quoted.
- [ ] 5.4 Add the fast subset (en+uk+ru, en+bg, en+de+fr) to the default suite. Verify: `swift test` runs it in under 30 seconds and passes.

## 6. Settings and UI

- [ ] 6.1 Let `SettingsManager.ambiguousLang` accept any admitted language or `off`. Verify: tests show `bg` round-trips, an unknown code falls back to `uk`, and stored `uk`, `ru` and `off` are unchanged.
- [ ] 6.2 Build the Auto-fix popup from the enabled admitted languages other than English, plus "do not convert", and show a stored but disabled value as unavailable without rewriting it. Verify: in the built app with English, German and French enabled, the popup lists Deutsch, Français and "do not convert", and toggling a layout off and on keeps the stored value.
- [ ] 6.3 Add flags for bg and any other admitted language to the caret and menu badge table. Verify: the menu shows 🇧🇬 when the Bulgarian layout is active.

## 7. Belarusian gate and Kazakh record

- [ ] 7.1 Re-test the user-installed dictionary route: install a Hunspell dictionary into `~/Library/Spelling`, log out and in, enable the language in Keyboard → Text Input → Spelling, and probe `availableLanguages` and `checkSpelling` with a word and with mash. Needs the user, because it requires a logout. Verify: the result, positive or negative, and the macOS version are recorded in the proposal, and the test files are removed afterwards.
- [ ] 7.2 Record the licence decision for the LibreOffice `be_BY` dictionary used through the system route or downloaded on request, not bundled. Needs the user. Verify: the decision and its reasoning are written into the proposal's Belarusian section.
- [ ] 7.3 If 7.1 is positive and 7.2 allows it: add the Belarusian profile and short-word list, Belarusian prose, and run the combination measurement with `be`. Verify: the gated run covers every combination with `be`, and admission or decline is recorded with its numbers. If 7.1 is negative: open a separate change for an in-app Hunspell reader and link it here.
- [ ] 7.4 Add a test that a layout whose language the spell checker does not list, such as Byelorussian or Kazakh on this Mac, never keeps or converts a word. Verify: the test passes against the real spell checker and prints the skip reason.

## 8. Windows, docs, verification

- [ ] 8.1 Regenerate `windows/src/Switcher3way.Core/ShortWords.cs` from the Swift file, writing a small generator script under `windows/tools/` if none exists. Verify: the diff adds only the new lists, and `dotnet test windows/tests/Switcher3way.Core.Tests` passes, or the task records that .NET was not available on this Mac.
- [ ] 8.2 Update `docs/user-guide.md`, `.uk.md` and `.ru.md` with the supported languages, why phonetic layouts are not auto-fixed, and the recall to expect from Latin pairs. Verify: `bash build_app.sh` regenerates the Help pages without errors.
- [ ] 8.3 Build and install the app, enable English and Bulgarian only, and confirm both directions from the debug log: a Bulgarian word typed on the English layout converts, and the same keystrokes typed on the Bulgarian layout are kept. Repeat with English, German and French. Verify: the log lines are quoted in this file.
- [ ] 8.4 Update the current-state and known-issues sections of `CLAUDE.md`, and run `openspec validate detect-chosen-language-combinations --strict`. Verify: validation passes.

## Bulgarian slice — measured 2026-10-14 (macOS 27, real NSSpellChecker and layouts)

Done ahead of de/fr: `LanguageProfile` (2.1–2.2, for en/uk/ru/bg; no `admitted` flag yet), the
transliterating-layout flag (3.1–3.3), same-script rescue ties (4.1), the bg short-word list,
vowels and canary (5.1–5.2 for bg), the `bg` preference and 🇧🇬 (6.1–6.3, popup shows Български when
a Bulgarian layout is enabled or `bg` is stored). Two findings changed the design:

- **An excluded phonetic layout must still witness.** Dropping Bulgarian Phonetic from the
  candidates let the rescue hand Bulgarian typed on it to English transliteration (`няколко` →
  `nqkolko`): 67/195 words wrong in en+uk+bgPh, 61/195 in en+ru+bgPh. A word on an excluded layout now
  keeps (`claimedByTransliteratingLayout`); wrong conversions back to 0.
- **English contractions are judged by grammar** (`Contractions`). Bulgarian `ч` sits on the
  apostrophe key and NSSpellChecker accepts `fr'd`, `w'go`, `l'ed`: 8 of 13 bg typos converting in
  en+bg. On a transliterating current layout the near-miss guard starts at 4 letters, not 6.

Typo conversions (own-language typos on own layout), before → after:

| combo | bg / bgPh | en | uk / ru |
|---|---|---|---|
| en+uk+ru (bar) | — | 0.26 → 0.26% | uk 0.30 → **0.28%**, ru 0.09 → 0.09% |
| en+bg | 0.39 → 0.15% | 0.00 → 0.06% | — |
| en+uk+bg | 0.51 → 0.27% | 0.23 → 0.23% | uk 0.21 → 0.19% |
| en+ru+bg | 0.57 → **0.33%** | 0.19 → 0.13% | ru 0.16 → 0.16% |
| uk+ru+bg | 0.24 → 0.24% | — | uk 0.21, ru 0.09 → 0.13% |
| en+bgPh | 0.36 → 0.00% | 0.55 → 0.00% | — |
| en+uk+bgPh | 0.39 → 0.00% | 0.75 → 0.19% | uk 0.17 → 0.13% |

Keep: 0 moved everywhere. Wrong: 0 everywhere for en/uk/ru/bg/bgPh combinations.
Recall: bg@en 152 → 154/195; bgPh as a target 149 → 0 (by design); en@bgPh 144 → 90/220 (the
lower guard on a phonetic layout).

**Gate status: one failure.** en+ru+bg Bulgarian typos 11/3340 (0.33%) against a bar of 0.28%.
The remainder are Bulgarian typos that are real Russian words on ЙЦУКЕН at four or five letters
(`мого`→`жара`, `итхо`→`кота`, `нещщо`→`лунна`) and real English words (`lier`, `lieu`, `fjord`),
below the band where the near-miss guard is trusted. Not tuned further: it shipped at 0.57% before
this change. Open decision.

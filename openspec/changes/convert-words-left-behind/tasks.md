# Tasks

## 1. Baseline

- [x] 1.1 Record the "before" numbers on `main`: `ShortWordPrecisionTests` output and the gated en+uk+ru, en+bg, uk+bg, ru+bg rows of `SWITCHER3W_MEASURE_COMBINATIONS=1 swift test --filter LanguageCombinationTests`. Verify: the figures are quoted under this task.
  - `main` at `9f1fffb` (the three later commits on `origin/main` touch no decision code), macOS 27,
    2026-11-13. Short-word coverage: en 50/50, uk 46/46, ru 82/82, bg 56/56 (100%). Full combination
    run: 736 rows; one gate failure, the open Bulgarian one: **en+ru+bg, bg typos 11/3340 (0.33%)**.

## 2. Phrase correction converts what it spans

- [x] 2.1 Add `WordKind.unrecognised(lang:)` to `PhraseTracker`, and re-render it inside a correction segment when its `lang` differs from the target. The segment start is still found from defaulted words only. Verify: new `PhraseTrackerTests` cases for both spec scenarios ("not left behind", "does not start"), plus the existing `testNeutralWordsAreReproducedVerbatim`, pass.
- [x] 2.2 In `AppDelegate.handleAutoConvert`, record a `.keep(.notAWordAnywhere)` word as `.unrecognised(lang: currentLanguageCode)`. Every other keep reason stays as it is. Verify: `swift build` succeeds and the debug log line for the keep is unchanged.
- [x] 2.3 Replay the four field episodes (10 Nov `z`, 11 Nov `d`, 11 Nov `dsy`+`ukj,fk`, 13 Nov `xbv z`) through `PhraseTracker` with the keystrokes and decisions from the log. Verify: each corrected segment comes out fully Ukrainian (`…, чим я допомогти`; `бо він глобал …`) in a regression test named after the date.
  - `WordsLeftBehindTests` replays them on the real US and Ukrainian-PC layouts: `не те щоб я`,
    `та ні, в`, `бо він глобал`, `Це все, чим я`. The log never records the word that triggered a
    correction, and that word is not part of the rewritten segment, so it is left out.

## 3. Short-word review

- [x] 3.1 Add `ShortWordReview.swift` to the test target: a recorded noise set per language for uk, ru and bg, and a test that enumerates every 1–3 letter string the live dictionary accepts and fails, naming the string, when it is in neither the list nor the noise set. Skips when the dictionary is unavailable. Verify: run on `main` first and record the number of unclassified strings per language here (expected to include `він`, `чим`).
  - On `main`'s lists (macOS 27, 2026-11-13): uk accepted 1342, listed 143, unclassified 1199; ru 2016 /
    133 / 1883; bg 1318 / 181 / 1137. All nine field-log words (`він чим от ото же їду йти тю ок`) are
    among the unclassified.
- [x] 3.2 Classify every unclassified Ukrainian string as a typed word (added to `ShortWords.swift`) or noise (added to the review's noise set). Colloquial and profane words people type count as typed words. Verify: the review test passes for uk, and `він чим от ото же їду йти тю ок` are admitted.
- [x] 3.3 The same for Russian. Verify: the review test passes for ru.
- [x] 3.4 The same for Bulgarian. Verify: the review test passes for bg.
  - Classified 2026-11-13: uk 497 typed / 702 noise, ru 723 / 1160, bg 381 / 756. A second test
    (`testNoListedWordHidesACommonEnglishWord`) renders every listed word on US. It caught 13 added words
    whose keys spell a common English word (`еру`/the, `рук`/her, `ща`/of, `шт`/in, `ікс`/src, `яд`/so,
    …). They are recorded as noise in `ShortWordReview.mirrors`. `ікс` was first kept by mistake and
    showed up on Windows as `src`→`ікс` in the vowel-less fixture. Kept knowingly, the English twin
    being rare: `см`/cv, `учу`/exe, `туш`/jwt. Function words on the lists before the review
    (`до`, `са`, `ви`, `мы`) are recorded as accepted, not re-decided.
- [x] 3.5 Add the words from the field log to `ShortWordFixture.inProse` (`він`, `чим`, `от`, `ото`, `же`, `їду`, `йти`) so the prose coverage measures them too. Verify: `ShortWordPrecisionTests` reports 100% coverage for uk, ru and bg.
  - Coverage after: uk 100% (55/55), ru 100% (82/82), bg 100% (56/56). The vowel-less rule's false
    conversions on macOS went 0/76 → 0/76. On the Western branch the same measurement read 2/76, both `см`→cv.
- [x] 3.6 Re-run the measurements from 1.1. Verify: keep 0 and wrong 0 in every gated row, typos at or under the 0.28% bar, and any row that moved is quoted with the additions that moved it.
  - After (final lists, 2026-11-13): all 736 rows identical to the baseline, and the same single gate
    failure (en+ru+bg 0.33%, pre-existing). Nothing moved, in either direction. This harness judges each
    word alone, with no phrase, and short words are held either way, so it cannot see the gain. The
    gain is in phrases: `WordsLeftBehindTests` replays the four field episodes. What it does confirm is
    no new damage: keep 0 and wrong 0 everywhere they were 0.

## 4. Windows

- [x] 4.1 Bring `windows/tools/gen-shortwords.py` over from the `western-languages` branch and regenerate `windows/src/Switcher3way.Core/ShortWords.cs`. Verify: `python3 windows/tools/gen-shortwords.py --check` passes, and the diff adds only words.
- [x] 4.2 Port the `unrecognised` word kind to the Windows `PhraseTracker` and `Engine`, with the `чим я` regression in `PhraseTrackerTests.cs`. Verify: `dotnet test windows/tests/Switcher3way.Core.Tests` passes, or this task records that .NET was unavailable.
  - `dotnet test` (net8.0 via `DOTNET_ROLL_FORWARD=Major`): 212 passed. Every printed figure is identical
    to `main`: paragraphs left 0/346 Latin and 0/344 Cyrillic, en typos 5/3117, per-language matrix
    unchanged. `ShortWords.cs` gains a Bulgarian list for the first time (Windows bundles bg).

## 5. Release

- [ ] 5.1 Build and install the app, enable debug logging, and type `Це все, чим я допомогти` with the US layout active in TextEdit and in Teams. Verify: the text ends fully Ukrainian, and the `auto:` log lines are quoted here.
- [x] 5.2 Bump `version.json` to 1.7.3 with update notes in en/uk/ru, update the current-state section of `CLAUDE.md`, and run `openspec validate convert-words-left-behind --strict`. Verify: validation passes and `bash build_app.sh` stamps 1.7.3.

## Workflow follow-up

- Archive the change after release.

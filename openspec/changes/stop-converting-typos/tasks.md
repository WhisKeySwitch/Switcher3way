## 1. Reproduce the report before designing anything

- [x] 1.1 Build a typo harness over the real ЙЦУКЕН↔QWERTY tables and the real dictionaries.
- [x] 1.2 First attempt measured 0/128 — long words only, whose Latin rendering is never an English word. Recorded as a failed reproduction rather than as "no problem found".
- [x] 1.3 Reproduce it on short words: 54/403 (13.4%) converted.
- [x] 1.4 Measure why: 160 of 676 two-letter Latin strings are in the English dictionary, mostly abbreviations.
- [x] 1.5 Measure precision and recall over natural prose, and note that most Ukrainian false positives go to **Russian**, not English.

## 2. Price every candidate cure in recall before choosing one

- [x] 2.1 Compare length floors, a typo veto, and their combinations on the same corpora, in both layout sets.
- [x] 2.2 Establish that no blunt policy works: the typo veto reaches 0% false positives but drops isolated en recall from 95% to 53%.
- [x] 2.3 Conclude that short words cannot be decided alone, and that the only further evidence available is context.
- [x] 2.4 Build a sequence-level simulation, since a policy that defers a decision can only be scored where a next word exists.
- [x] 2.5 Sweep the near-miss test's false-alarm rate by word length; find it worthless below 6 and exactly 0% at 6+.

## 3. Implement

- [x] 3.1 `TypoGuard.NearMiss` — Damerau–Levenshtein distance one against the dictionary.
- [x] 3.2 `IDictionaryValidator.Alphabet`, defaulted to `""` so existing fakes compile and degrade to the old behaviour.
- [x] 3.3 Hunspell supplies it from the dictionary's own `TRY` line, lower-cased and de-duplicated.
- [x] 3.4 `Outcome.Defer`, and `Outcome.Keep.ValidInCurrent` so the engine can pin the phrase.
- [x] 3.5 Resolver: phrase arbitrates below 6, near-miss vetoes from 6 up, `Defer` below 4 with nothing settled.
- [x] 3.6 Manual trigger bypasses both guards — an explicit request is entitled to an answer.
- [x] 3.7 Engine: pass the phrase language in, handle `Defer`, pin the phrase on a word already valid.
- [x] 3.8 Engine: settle a run of two agreeing held words, so an all-short message still converts.
- [x] 3.9 Pair phrase reset with held-run reset in one method, so the two can never be reset apart.

## 4. Verify

- [x] 4.1 Ukrainian and English typo rates: 2.86% / 2.19% → 0.00% / 0.00%.
- [x] 4.2 Short-typo rate 13.4% → 0.00%.
- [x] 4.3 Paragraph recovery unchanged in both directions, with both layout sets.
- [x] 4.4 Fumbled paragraph: 0 words mangled, 0 spurious layout switches.
- [x] 4.5 `як ти пишеш` in the wrong layout: two words held, then converted by the word that settles it.
- [x] 4.6 `як ти?` — all words too short — converted by the two of them agreeing.
- [x] 4.7 Benchmark `NearMiss`: 0.04–0.6 ms on a hit, 4–7 ms on a miss.
- [x] 4.8 Full suite green (177).
- [ ] 4.9 Exercise a packaged build by hand: type a Ukrainian paragraph with deliberate typos and confirm the layout never moves.

## 5. Document

- [x] 5.1 Spec delta for `layout-switching-and-language-detection`.
- [ ] 5.2 User guide (en/uk/ru): say that typos are left alone and that very short words wait for context.
- [ ] 5.3 `CLAUDE.md` and `windows/RELEASING.md` status.

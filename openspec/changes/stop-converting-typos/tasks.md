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
- [x] 4.8 Full suite green (178).
- [x] 4.9 First hand-verification attempt was inconclusive, and usefully so — see section 6.
- [x] 4.10 Re-run on the 0.3.1 sideload build, reading the decisions out of the log rather than inferring
      them from the screen. Ukrainian paragraph with the exact typos that used to convert — `рукую`
      (reads `here.`), `ае` (`ft`), `даже` (a real Russian word), `ща` (`of`) — all kept, **zero
      conversions and zero layout switches**; then `ghbdsn` with the English layout active still
      converted to `привіт` and moved the layout, so the app is demonstrably not just inert.
      Scripted in `windows/tools/verify-typo-guard.py` so it can be re-run.

## 5. Document

- [x] 5.1 Spec delta for `layout-switching-and-language-detection`.
- [x] 5.2 User guide (en/uk/ru): say that typos are left alone and that very short words wait for context.
- [x] 5.3 `CLAUDE.md` and `windows/RELEASING.md` status.

## 6. Make the decision visible, because the first attempt could not see it

The first attempt to verify this by hand reported "nothing was converted", and neither the tester nor
the log could tell which of three very different things had happened.

- [x] 6.1 Establish from the log what actually ran. `secure: …` appeared 27 times — that line is written
      at the top of `AutoConvert` — so every word *was* evaluated and reached the resolver.
- [x] 6.2 Establish which binary produced it: the **Store build 0.3.0, started 19 August**, which does
      not contain this change. The test could not have exercised the fix either way. Asking for
      verification without supplying a build was the mistake.
- [x] 6.3 Note the deeper problem, which would have bitten the next attempt too: `Outcome.Keep` logged
      **nothing**. Leaving a word alone is this app's most common decision and it changes nothing on
      screen, so a guard working perfectly and a guard never running produced identical evidence. This
      change made `Keep` the outcome that carries the new behaviour and left it silent — the fix was
      unverifiable by construction.
- [x] 6.4 Give `Outcome.Keep` a `KeepReason`, and log every decision with a plain-language reason.
- [x] 6.5 Test that each reason is reported correctly, so the log is worth trusting. Writing it caught
      one of my own examples being wrong: `програмаа` is not a word in English either, so no conversion
      was ever on the table and the near-miss guard is never consulted.
- [x] 6.6 Build a signed sideload MSIX stamped **0.3.1**, so which build is running is never in doubt
      again, and confirm by extracting the package that the new code is actually inside it.

## 7. Port to macOS

The defect was structural, so it was in the Swift resolver too, in the same shape.

- [x] 7.1 `Sources/Switcher3wCore/TypoGuard.swift` — port of the Windows guard.
- [x] 7.2 `DictionaryValidating.alphabet(_:)`, defaulted to `""` via a protocol extension, so existing
      conformances compile and an adapter that cannot answer degrades instead of vetoing everything.
- [x] 7.3 `SystemDictionary.alphabet(_:)` derives the letters from the keyboard layout of that
      language and caches them. `NSSpellChecker` has no equivalent of Hunspell's `TRY` line, and the
      layout is arguably the more direct source anyway.
- [x] 7.4 `Outcome.keep(KeepReason)` and `Outcome.held` — the Swift counterparts of `Keep(KeepReason)`
      and `Defer`. Existing `guard case .keep` sites keep compiling; every construction site updated.
- [x] 7.5 Resolver: phrase arbitrates below 6, near-miss vetoes from 6 up, `held` below 4 with nothing
      settled; `manualPlan` evaluates unguarded.
- [x] 7.6 `AppDelegate`: pass the phrase language in, log the keep reason, pin the phrase on a word
      already valid, handle `held`, and settle a run of two agreeing held words through the existing
      phrase-correction machinery. `resetPhrase()` pairs the phrase and the held run so neither can be
      reset without the other.
- [x] 7.7 `Tests/Switcher3wCoreTests/TypoGuardTests.swift` — 11 cases mirroring the Windows ones.
- [x] 7.8 Guard `DictionaryQualityTests` with `#if canImport(AppKit)`: it is the only test tied to
      Apple's frameworks, and without that the platform-independent core cannot be built or exercised
      anywhere else.

### What is and is not verified

- [x] 7.9 `Switcher3wCore` **compiles** on the Windows toolchain, and every assertion in the new test
      file was **executed** there against the compiled core through a standalone harness — XCTest
      itself cannot run here (swift-corelibs-xctest fails to cast `@MainActor` test methods). 12/12
      checks pass: reasons reported correctly, typos kept, short words held and then repaired by the
      word that settles the phrase, long wrong-layout words still converted, the manual trigger not
      second-guessed, and the guard degrading safely with no alphabet.
- [x] 7.10 The test target compiles.
- [x] 7.11 **On a Mac:** `swift test` (the XCTest run proper, including the NSSpellChecker
      dictionary-quality test), then `bash build_app.sh` — `Sources/Switcher3w/` is AppKit-bound and
      has only been syntax-checked here, never type-checked. Done 2026-08-22: 69 tests, 0 failures
      (dictionary-quality at 100% for en/uk/ru); `build_app.sh` produced a bundle signed with the
      stable `Switcher3way Self-Signed` identity, `codesign --verify` clean.
- [ ] 7.12 **On a Mac:** the same by-hand pass the Windows build got — type a Ukrainian paragraph with
      deliberate typos and confirm from `~/Library/Logs/Switcher3w/switcher3w.log` that every word
      reports `auto: keep — …` and the layout never moves, then type a word in the wrong layout and
      confirm it still converts.

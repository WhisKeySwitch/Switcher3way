## 1. Decide which languages, by measurement

- [x] 1.1 Build the cross-language collision matrix over the real dictionaries, through the app's own
      validator. Result in the proposal; it contradicted the prediction twice.
- [x] 1.2 Separate *overlap* from *risk*: overlap only becomes ambiguity when two layouts render the
      same keys identically. Bulgarian (BDS) and Serbian (QWERTZ-aligned) do not share ЙЦУКЕН, which
      reverses the ranking the matrix alone suggests.
- [x] 1.3 Measure what adding them costs the users already here: **0.00% → 0.00%** on both typo
      corpora, in the worst case where the candidates are rendered through ЙЦУКЕН.
- [x] 1.4 Audit licences. `bg` and `sr` are tri-licensed with MPL-1.1 selectable; `be` is CC BY-SA 4.0
      or LGPLv3 with no permissive branch; `mk` is GPL-3.0 only; `kk`/`ky`/`tg` have no free
      dictionary in either source.
- [x] 1.5 Measure the package cost: **bg 0.30 MB, sr 1.14 MB compressed** (en/ru/uk today are
      0.19/0.60/1.57 MB).
- [x] 1.6 Find what the shape heuristic gets wrong: Serbian syllabic R. Recorded, with the reason the
      aggregate number hid it.

## 2. Bundle the dictionaries

- [x] 2.1 Added from LibreOffice `bg_BG` and `sr`, with licence files. **The licence check changed the
      story.** The proposal claimed MPL-1.1 for Bulgarian on the strength of `wooorm/dictionaries`'
      metadata; the licence file it links to contains no licence statement, and LibreOffice ships only
      a GPL-2 `COPYING`. The tri-licence is real but is stated by the upstream **bgOffice** project,
      and that statement is now quoted in `dict/bg.license` so the evidence travels with the file.
      Serbian is explicit in its own README — LGPL-3 / **MPL-2** / GPL-3, reader's choice — and is
      MPL **2.0**, not the 1.1 the packager's table claimed.
- [x] 2.2 `DICTIONARIES.md` carries both, the Bulgarian licence trail, the declined languages with
      their reasons, and why `sr-Latn` is deliberately **not** bundled: Serbian Latin and Cyrillic are
      a 1:1 transliteration of one language, so shipping both would make every Serbian word valid in
      two "languages" and turn ordinary typing into permanent ambiguity.
- [x] 2.3 Dictionaries go from **2.42 MB to 3.80 MB** compressed (bg 0.30, sr 1.14), as predicted.

## 3. Teach the heuristics about them

- [x] 3.1 Vowel sets added: `bg` → `аеиоуъюя`, `sr` → `аеиоур` (see 3.2).
- [x] 3.2 Measured both, and they came out equivalent, so the simpler one wins — widening the vowel
      set, which is also the linguistically honest description, since syllabic R *is* a syllable
      nucleus in Serbian.

      | option | real Serbian judged implausible | gibberish judged Serbian |
      |---|---|---|
      | today (`аеиоу`) | 50 / 30,000 — **0.17%** | 98.35% |
      | widen (add `р`) | 6 / 30,000 — **0.02%** | 98.83% |
      | rule (`р` excuses the vowel, still counts as a consonant) | 6 / 30,000 — **0.02%** | 98.83% |

      **The control was wrong the first time and had to be rebuilt.** It began as "Russian and
      Ukrainian words", which the shape test accepted at 86% — correctly, since those *are* words, and
      the test distinguishes words from keyboard gibberish rather than one Slavic language from
      another. Replaced with what the rescue is actually shown: English typed on a Serbian layout.

      **That rebuilt control then revealed something larger than syllabic R.** 98% of it reads as
      plausible Serbian — because the Serbian Cyrillic layout is positionally aligned with Latin, so
      **vowels map to vowels** and word shape survives the wrong layout intact. ЙЦУКЕН scrambles it
      (`q`→`й`, `e`→`у`), which is why the rescue works well for Ukrainian and Russian. For Serbian
      the shape signal is weak, so the rescue will rarely fire — and safely, because two plausible
      candidates means "keep". Serbian gains the dictionary path; it gains little from the rescue.
      Worth knowing before anyone reads a quiet log and calls it a bug.
- [ ] 3.3 Extend the shape fixture with real Serbian and Bulgarian must-keep tokens, so the thresholds
      are measured for these languages rather than inherited from the ones they were tuned on.

## 4. Verify

- [ ] 4.1 Collision matrix and the degradation test re-run with the dictionaries bundled rather than
      staged; the existing corpora must still convert **0.00%** of typos.
- [ ] 4.2 A Bulgarian and a Serbian sentence typed in the wrong layout convert; the same sentences
      typed correctly are left alone.
- [ ] 4.3 The syllabic-R words specifically: `крв`, `прст`, `врх`, `трг`, `црн`, `брз`, `крст`, `врт`,
      `смрт` typed correctly in Serbian are not converted into anything.
- [ ] 4.4 Windows end-to-end on a packaged build, as `rescue-wrong-layout-gibberish` task 5.3 did.
- [ ] 4.5 macOS: the same core changes, with `NSSpellChecker` rather than bundled dictionaries — note
      that macOS may not *have* Bulgarian or Serbian dictionaries installed, in which case the
      language is simply skipped, and that difference should be checked rather than assumed.

## 5. Say so

- [ ] 5.1 Store listing, what's-new and release notes in the existing three languages. Whether the
      listing itself should also be offered in Bulgarian and Serbian is a separate decision.
- [ ] 5.2 Record in `RELEASING.md` that the bundled-dictionary count has grown, and that this is the
      point at which on-demand dictionaries were said to become worth reconsidering.

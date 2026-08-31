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

- [ ] 2.1 Add `bg.dic`/`bg.aff` and `sr.dic`/`sr.aff` from LibreOffice `bg_BG` and `sr`, with their
      licence files, relying on and recording the **MPL-1.1** branch.
- [ ] 2.2 Update `DICTIONARIES.md` with both, in the same table and with the same "why not the other
      one" reasoning already there for Ukrainian.
- [ ] 2.3 Confirm the packaged size against the measurement before and after.

## 3. Teach the heuristics about them

- [ ] 3.1 Vowel sets: `bg` → `аеиоуъюя` (ъ is a vowel in Bulgarian), `sr` → `аеиоу`.
- [ ] 3.2 Serbian syllabic R: a word with no vowel but an R between consonants is a normal Serbian
      word, not gibberish. Decide between widening the vowel set and a Serbian-specific rule, and
      justify it with the false-conversion rate each produces rather than by taste.
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

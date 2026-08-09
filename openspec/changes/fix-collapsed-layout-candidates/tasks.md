## 1. Keystroke path (`NWayResolver.manualPlan`)

- [x] 1.1 Extract the tie-break into one place: given the `evaluate` outcome and the ambiguity
      preference, return the layout id that a collapsed candidate should carry (dictionary winner →
      preferred ambiguity language if among the winners → nil for "leave as is")
- [x] 1.2 ~~Track which layouts were dropped by the dedup~~ — **not needed on this path.** Candidates
      are unique by rendered string, so a winner that is absent by layout id but present by text was
      necessarily collapsed into that entry: the existing text match IS the collapse signal. The
      selection path (2.2) does keep an explicit list, because there the winner has to be *found*
      among the dropped entries before it can be validated, not merely matched
- [x] 1.3 At the promotion site, when the winning layout was collapsed away, rewrite the surviving
      candidate's `targetLayoutID` instead of only reordering — and move it first
- [x] 1.4 Leave the candidate count unchanged; assert this in a test rather than by inspection

## 2. Selection path (`TextConverter.buildSelectionSteps`)

- [x] 2.1 Replace the "promote only when exactly one candidate validates" rule with the same three
      rungs, reading `SettingsManager.shared.ambiguousLang` for rung 2
- [x] 2.2 Apply the same survivor-layout correction when a candidate was dropped by its `seen` dedup
- [x] 2.3 Cross-reference the two builders in comments — each says the rule also lives in the other,
      so the next edit to one is a prompt to check the other

## 3. Tests

- [x] 3.1 Flip `testCollapsedRenderKeepsTheFirstLayoutEvenForAnUnambiguousWinner`: `хорошо`
      (Russian-only, renders identically in uk) SHALL now yield the Russian layout
- [x] 3.2 Flip `testAmbiguousWordIgnoresThePreferenceWhenRendersCollapse`: `добре` with the
      preference set to uk / ru SHALL yield that layout, and one candidate either way
- [x] 3.3 New: preference "off" on an ambiguous word falls back to rotation order
- [x] 3.4 New: a preference naming a language that is NOT among the winners does not drag the
      candidate there (`місто` with the preference set to ru stays Ukrainian)
- [x] 3.5 New: no dictionary evidence at all → rotation order, unchanged from today
- [x] 3.6 Keep `testPreferencePromotesWhenBothLayoutsRenderDifferently` and
      `testIdenticalRendersAreOfferedOnce` green — differing renders and cycle length must not change
- [x] 3.7 `swift test` passes

## 4. Manual verification (selection path — not reachable from the core suite)

- [x] 4.1 Build and install; with EN active, select text rendering as `хорошо` and trigger →
      Russian layout, text unchanged
- [x] 4.2 Same for an ambiguous selection (`добре`) with the preference set to uk, then ru —
      **FAILED on the first implementation** (cycled uk↔en only, ru unreachable). Root cause and
      the revised D1 are in `design.md`; re-verify below
- [x] 4.3 Confirm repeated triggers still cycle and that the final tap restores the original text
      AND the exact pre-conversion layout

## 4b. Re-verification after the D1 reversal

- [x] 4b.1 De-duplicate by text AND language in `NWayResolver.manualPlan`; drop the
      survivor-layout rewrite, which the change makes unnecessary
- [x] 4b.2 Same in `TextConverter.buildSelectionSteps`; drop its `collapsed` list for the same reason
- [x] 4b.3 Tests: uk/ru remain two reachable steps; the preference decides which LEADS; two layouts
      of the same language still collapse (new fixture layout `ru2`)
- [x] 4b.4 Log the selection path's steps and the live preference, so "the preference is ignored" is
      readable from the log instead of inferred — the lesson from the Windows password guard
- [x] 4b.5 **User re-check:** with a Cyrillic selection of `добре` in uk, the trigger reaches ru;
      with the preference set to ru it leads

## 4d. Third reachability path: the cycle seeded by an automatic conversion

- [x] 4d.1 `handleAutoConvert` seeded ONE step, so after an auto-fix the trigger toggled between the
      conversion and the original and never reached a third layout (`dblyj` → `видно` uk, ru
      unreachable). Seed the full N-way plan, applied candidate first
- [x] 4d.2 Keep the single step for phrase corrections — `home` is a whole segment there
- [x] 4d.3 Log the seeded cycle so its shape is readable from the log
- [x] 4d.4 Update the user guide in all three languages: cancelling an Auto-fix is no longer always
      one tap
- [x] 4d.5 **User confirmed:** `dblyj` cycles uk → ru → original → uk

## 4c. Test-suite defect found while re-verifying

- [x] 4c.1 `DictionaryQualityTests` was non-deterministic: it computed `accepted` and `rejected` in
      two separate passes over `NSSpellChecker`, which does not answer identically on back-to-back
      calls — it reported a 0.75 rate alongside an empty accepted list, arithmetic only possible if
      the passes disagreed. Now asks once per word, after a per-language warm-up call
- [x] 4c.2 Confirm stability across repeated runs

## 5. Docs and close-out

- [x] 5.1 `docs/user-guide.md` + `.uk.md` + `.ru.md`: a sentence in the trigger section on what
      happens when two layouts render a word identically
- [x] 5.2 Note the behavior change in the release notes — muscle memory attaches to the trigger, so
      this should not ship silently
- [x] 5.3 `openspec validate fix-collapsed-layout-candidates --strict`, then archive

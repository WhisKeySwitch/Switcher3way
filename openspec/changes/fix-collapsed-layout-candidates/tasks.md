## 1. Keystroke path (`NWayResolver.manualPlan`)

- [ ] 1.1 Extract the tie-break into one place: given the `evaluate` outcome and the ambiguity
      preference, return the layout id that a collapsed candidate should carry (dictionary winner →
      preferred ambiguity language if among the winners → nil for "leave as is")
- [ ] 1.2 Track which layouts were dropped by the dedup, so the promotion step can tell a collapse
      from a genuinely absent candidate
- [ ] 1.3 At the promotion site, when the winning layout was collapsed away, rewrite the surviving
      candidate's `targetLayoutID` instead of only reordering — and move it first
- [ ] 1.4 Leave the candidate count unchanged; assert this in a test rather than by inspection

## 2. Selection path (`TextConverter.buildSelectionSteps`)

- [ ] 2.1 Replace the "promote only when exactly one candidate validates" rule with the same three
      rungs, reading `SettingsManager.shared.ambiguousLang` for rung 2
- [ ] 2.2 Apply the same survivor-layout correction when a candidate was dropped by its `seen` dedup
- [ ] 2.3 Cross-reference the two builders in comments — each says the rule also lives in the other,
      so the next edit to one is a prompt to check the other

## 3. Tests

- [ ] 3.1 Flip `testCollapsedRenderKeepsTheFirstLayoutEvenForAnUnambiguousWinner`: `хорошо`
      (Russian-only, renders identically in uk) SHALL now yield the Russian layout
- [ ] 3.2 Flip `testAmbiguousWordIgnoresThePreferenceWhenRendersCollapse`: `добре` with the
      preference set to uk / ru SHALL yield that layout, and one candidate either way
- [ ] 3.3 New: preference "off" on an ambiguous word falls back to rotation order
- [ ] 3.4 New: a preference naming a language that is NOT among the winners does not drag the
      candidate there (`місто` with the preference set to ru stays Ukrainian)
- [ ] 3.5 New: no dictionary evidence at all → rotation order, unchanged from today
- [ ] 3.6 Keep `testPreferencePromotesWhenBothLayoutsRenderDifferently` and
      `testIdenticalRendersAreOfferedOnce` green — differing renders and cycle length must not change
- [ ] 3.7 `swift test` passes

## 4. Manual verification (selection path — not reachable from the core suite)

- [ ] 4.1 Build and install; with EN active, select text rendering as `хорошо` and trigger →
      Russian layout, text unchanged
- [ ] 4.2 Same for an ambiguous selection (`добре`) with the preference set to uk, then ru
- [ ] 4.3 Confirm repeated triggers still cycle and that the final tap restores the original text
      AND the exact pre-conversion layout

## 5. Docs and close-out

- [ ] 5.1 `docs/user-guide.md` + `.uk.md` + `.ru.md`: a sentence in the trigger section on what
      happens when two layouts render a word identically
- [ ] 5.2 Note the behavior change in the release notes — muscle memory attaches to the trigger, so
      this should not ship silently
- [ ] 5.3 `openspec validate fix-collapsed-layout-candidates --strict`, then archive

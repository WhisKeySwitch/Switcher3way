# Design — Phrase-Aware Ambiguity Resolution

## Context

`NWayResolver.resolve` renders the typed keycodes through every installed layout with a dictionary and converts only when exactly one other language validates the word; two or more winners (the uk/ru pair share most of their vocabulary shapes) collapse to `nil` → "keep" (NWayDetector.swift:99-101). Live testing confirmed «добре» is dictionary-valid in BOTH uk and ru, so the most common words stay as Latin gibberish while unambiguous neighbors convert. The word buffer already resets on Enter/Tab/arrows/clicks/app switches (KeyboardMonitor `fullReset`/`resetBuffersOnClick`), and the retype engine is now abortable with restore-on-abort (change `fix-retype-typing-race`) — a hard prerequisite, since phrase corrections erase multi-word segments.

## Goals / Non-Goals

**Goals:**
- Ambiguous words convert immediately to a preferred language (setting, default uk) — no more «Lj,ht?» left behind.
- The phrase self-corrects when its language is disambiguated later by a single-language word.
- Every replacement stays undoable by ⌥ and abortable by concurrent typing.
- Precision-first is preserved: contradictory phrases and "off" mode change nothing.

**Non-Goals:**
- Remote-desktop mode (forwarded chars go through the 2-way script path; no phrase tracking there).
- Re-converting words the user typed *correctly* (valid in the typed language) or words locked to a language — only ambiguity-defaulted words are ever touched retroactively.
- Sentence-level NLP. "Phrase language" is decided purely by the first exactly-one-language word.

## Decisions

1. **Resolver returns the ambiguity instead of swallowing it.** New `NWayResolver.evaluate(keys:capsLock:) -> Outcome` where `Outcome` is `.keep` / `.convert(Decision)` / `.ambiguous([Winner])`, `Winner = (lang, layoutID, converted)`. The existing `resolve` becomes a thin wrapper returning `Decision?` only for `.convert` (manualPlan and the remote path keep working unchanged). *Alternative:* applying the preference inside `resolve` — rejected: the choice depends on phrase lock state, which the resolver shouldn't know.

2. **New `PhraseTracker` (@MainActor, own file) holds the phrase.**
   - `PhraseWord { keys: [TypedKey], shownText: String, spacesAfter: Int, kind }`, `kind ∈ defaulted(lang) | locked(lang) | neutral`.
   - Recorded at each evaluated boundary with what actually ended up on screen (original render for keep, converted text for conversions) — recorded from the retype **success** completion; an aborted retype resets the tracker (screen state no longer certain — precision-first).
   - `spacesAfter` starts at 1 (the boundary space) and increments via a monitor hook when extra spaces arrive without a new word; any event the tracker can't account for (backspace past a word start, Enter, arrows, click, focus/app change, secure-input bail) resets the phrase. Erase math must be provably exact or the phrase dies.
   - `correction(to lang/layout)` returns `(oldSegment, newSegment, eraseCount)` spanning from the first defaulted-to-another-language word through the last word: defaulted words re-render their keys through the target layout (`DynamicKeyMapping`), neutral/locked words contribute `shownText` verbatim, spaces reproduced from `spacesAfter`.

3. **Orchestration stays in `handleAutoConvert`.**
   - `.convert(decision)` where the phrase holds defaulted words of a different language and no conflicting lock → build the correction segment *including the current word* and run it as ONE `beginCycle` (home = old segment, single step = corrected segment). One erase-insert, one layout switch, standard ⌥-undo of the whole correction for free.
   - `.ambiguous(winners)` → preferred = phrase lock, else the setting; if a winner matches, convert that single word and record it as `defaulted`; `"off"` or no match → keep (today's behavior).
   - Contradictory phrase (lock in one language, one-language word in another) → convert only the current word (existing rule), no retroaction.
   - Segment cap: if the correction erase exceeds 200 characters, skip the correction (log it) and convert only the current word — bounds worst-case erase chains.

4. **Setting `com.switcher3w.ambiguousLang`** — string `"uk"` (default) / `"ru"` / `"off"`, read live (no restart). UI: popup row on the Auto-fix tab via the existing `FormBox` factories; L10n strings added for en/uk/ru (`s()` falls back to English for the other 13). Language names shown as own-language fixed strings («Українська», «Русский»).

5. **Manual trigger ordering follows the preference.** `manualPlan` puts the dictionary winner first; when `resolve` yields nothing because of ambiguity, the preferred-language candidate is promoted to the front instead — one ⌥ tap gives the same answer auto-fix would.

## Risks / Trade-offs

- [Multi-word erase chains are long] → prerequisite abort guard covers concurrent typing; 200-char cap bounds the rest; correction is a single undoable cycle.
- [Erase-count drift (double spaces, edits inside the phrase)] → tracker resets on anything it can't account for exactly; a reset only costs the retro-correction, never text integrity.
- [NSSpellChecker false positives could lock a phrase to ru incorrectly] → damage is bounded: only ambiguity-defaulted words get re-rendered, and by definition they are valid in the locking language too; ⌥ undoes the whole segment.
- [«добре» converts to uk in a genuinely russian phrase start] → that's the designed trade-off; the phrase self-corrects at the first ru-only word, and the setting can flip the default to ru.
- [More retypes than before for ambiguous-heavy text] → each is a single word; the phrase correction batches the rest.

## Open Questions

_None — behavior decisions were confirmed with the user (setting with uk default; correction touches only defaulted words; phrase bounds = existing reset events)._

# Design — Windows Phrase-Aware Ambiguity Resolution

## Context

The macOS implementation (`NWayResolver.evaluate` + `PhraseTracker` + `fix-retype-typing-race`
abort guard) is the reference; this change ports it to the C#/.NET Windows build. The Windows Core
mirrors macOS closely already: `NWayResolver.Resolve` (`NWayResolver.cs:31`) renders keys through
every dictionaried layout and converts on exactly one winner, collapsing ≥2 winners to `null`
(`NWayResolver.cs:87`). The word buffer already resets on the right events
(`KeyboardMonitor.cs`: `ClearBuffer` on mouse/app-switch, `Reset` kind on arrows). The gaps: the
resolver hides ambiguity, there is no phrase memory, and `TextRewriter.Rewrite`
(`TextRewriter.cs:17`) is **not** abort-safe (no concurrent-typing check, no restore) — a hard
prerequisite because segment corrections erase multiple words.

Threading is the key Windows-specific difference from macOS (which is all `@MainActor`): the auto
path runs on a single **worker thread** draining `Engine._work` (`Engine.cs:33,116`), while resets
fire on the **hook thread**. Serializing all phrase mutation on the worker (route resets through
`_work`) keeps `PhraseTracker` lock-free, and a generation counter still guards the async gap.

## Goals / Non-Goals

**Goals:**
- Windows reaches behavioral parity with macOS v1.2.0 for ambiguity + phrase correction.
- Ambiguity logic lives in `Switcher3way.Core` (portable, covered by the existing test project).
- Every replacement (single word or multi-word segment) is abort-safe and undoable via the manual cycle.
- Precision-first preserved: contradictory phrases and `"off"` change nothing.

**Non-Goals:**
- Remote-desktop / forwarded-char input (already bailed out of the N-way path; no phrase tracking).
- Re-converting words typed correctly or locked to a language — only defaulted words move retroactively.
- Sentence-level NLP; "phrase language" is the first exactly-one-language word.
- Windows auto-update or signing (unrelated; tracked elsewhere).

## Decisions

1. **`Evaluate` in Core returns the ambiguity; `Resolve` stays a wrapper.**
   Add `Outcome` = `Keep | Convert(Decision) | Ambiguous(string Original, IReadOnlyList<Winner> Winners)`
   and `Winner(string Lang, string LayoutId, string Converted)` to `Types.cs`. `NWayResolver.Evaluate`
   holds the current logic but returns `Ambiguous` instead of `null` when `winners.Count > 1`;
   `Resolve` returns `d` only for `Convert` (keeps `ManualPlan` and existing callers stable). Winners
   must carry `Lang` (the Windows `Layout` already exposes `Lang`), which the current `winners` list
   omits — extend it. *Alternative:* apply the preference inside `Resolve` — rejected: the choice
   depends on phrase-lock state the resolver must not know.

2. **`PhraseTracker` in `Switcher3way.Core`, not the App.**
   macOS keeps it in the app because everything is `@MainActor`; on Windows the Core is the portable,
   tested layer, so the tracker (pure data + a correction builder) belongs there and gets unit tests.
   It renders defaulted words via an injected `Func<IReadOnlyList<TypedKey>, string, string?>`
   (`(keys, layoutId) => rendered`) backed by `NWayResolver.Render`, so Core has no Win32 dependency.
   Shape mirrors macOS: `PhraseWord(Keys, ShownText, SpacesAfter, Kind)`,
   `Kind ∈ Defaulted(lang) | Locked(lang) | Neutral`; `Correction(OldSegment, NewSegment, FirstIndex,
   CorrectedWords)`; `Generation` counter; `MaxCorrectionLength = 200`.

3. **Orchestration in `Engine.AutoConvert`, single-threaded on the worker.**
   - Compute `Evaluate`. Record the outcome into the tracker with what actually reached the screen
     (rendered-current for keep, converted text for a conversion) — recorded **after** a successful
     rewrite; a failed/aborted rewrite resets the tracker (screen state uncertain).
   - `Convert(d)` where the phrase holds defaulted words of another language and no conflicting lock
     → build the correction (first defaulted-to-other word … current word) and apply it as ONE
     rewrite (erase old segment, insert new segment) then one layout switch — undoable as a unit by
     the manual cycle. Else convert just the current word (existing path).
   - `Ambiguous(winners)` → target = phrase lock, else the `AmbiguousLang` setting; if a winner
     matches, convert that one word and record it `Defaulted(lang)`; `"off"`/no match → keep.
   - Reset the phrase when the boundary is Enter/Tab (`boundary != ' '`) after processing the word,
     and on the marshaled `PhraseReset`. `SpacesAfter` starts at 1 and increments on extra spaces.
   - 200-char segment cap: over it, skip the correction (log) and convert only the current word.

4. **Abort-safe `TextRewriter` (prerequisite).**
   Add a shared, monitor-owned abort flag: `KeyboardMonitor` sets it on any real (non-injected)
   keystroke while a rewrite is in progress; the engine arms it before a rewrite and the rewriter
   checks it between injected characters. On abort, the rewriter re-inserts the characters it already
   erased (it knows the erased count and the original text it is replacing) and returns a new
   `Result.Aborted`; the engine treats abort as "did not happen" (no phrase record; tracker reset).
   The single-word path gets the same guard for free. This mirrors the macOS `fix-retype-typing-race`
   change that the phrase work depends on.

5. **`AmbiguousLang` setting, live.**
   `SettingsManager.AmbiguousLang` (string, default `"uk"`; `"ru"`, `"off"`), persisted in the JSON
   settings, read live. `SettingsForm` Auto-fix tab: a labeled `ComboBox` (Українська / Русский /
   Do not convert) mapped by value, applied on Save. `Loc.cs` regenerated to include the ambiguity
   strings from the macOS `Localization.swift` (fallback to English for languages lacking them).

6. **Manual trigger promotes the preference under ambiguity.**
   `ManualPlan` switches from calling `Resolve` to `Evaluate`; on `Ambiguous`, if the preferred
   language (setting) has a winner, promote that candidate to the front — one trigger tap gives the
   same answer auto-fix would, matching macOS `manualPlan`.

## Risks / Trade-offs

- **Multi-word erase chains are long** → the new abort guard covers concurrent typing; the 200-char
  cap bounds the rest; a correction is one undoable rewrite.
- **Erase-count drift (double spaces, mid-phrase edits)** → the tracker resets on anything it can't
  account for exactly (backspace into a prior word, arrows, click, app switch, focus loss); a reset
  costs only the retro-correction, never text integrity.
- **Hunspell false positives could lock a phrase to the wrong language** → bounded: only
  ambiguity-defaulted words re-render, and by definition they are valid in the locking language too;
  the whole segment is undoable.
- **«добре» converts to uk in a genuinely Russian phrase start** → designed trade-off; the phrase
  self-corrects at the first ru-only word, and the setting can flip the default to ru.
- **Cross-thread reset ordering** → resets marshaled through `_work` are FIFO-ordered with word
  events, so a reset can never interleave a phrase mutation; the generation counter drops any record
  that still loses a race.

## Open Questions

_None — the behavior is already specified (platform-neutral `automatic-conversion-on-word-boundaries`)
and confirmed on macOS; this is a parity port with Windows-specific threading/rewrite adaptations._

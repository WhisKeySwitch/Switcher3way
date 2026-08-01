# Tasks — Windows Phrase-Aware Ambiguity Resolution

## 1. Core: expose ambiguity

- [x] 1.1 Add `Winner(string Lang, string LayoutId, string Converted)` and
  `Outcome` (`Keep` / `Convert(Decision)` / `Ambiguous(string Original, IReadOnlyList<Winner> Winners)`)
  to `windows/src/Switcher3way.Core/Types.cs`.
- [x] 1.2 In `NWayResolver.cs`, extract the current `Resolve` body into `Evaluate(keys, capsLock) -> Outcome`:
  build the winners list carrying `Lang`; return `Convert` for exactly one, `Ambiguous` for more than
  one, `Keep` otherwise (and for always-convert / already-valid / unresolvable-layout cases).
- [x] 1.3 Make `Resolve` a thin wrapper returning the `Decision` only for `Convert` (existing callers unchanged).
- [x] 1.4 Add `Render(keys, layoutId) -> string?` and `RenderCurrent(keys) -> string?` to `NWayResolver`
  (look up the layout by id / current, reuse `_layouts.Render`).

## 2. Core: PhraseTracker

- [x] 2.1 Add `windows/src/Switcher3way.Core/PhraseTracker.cs`: `WordKind` (`Defaulted(lang)`/`Locked(lang)`/`Neutral`),
  `PhraseWord(Keys, ShownText, SpacesAfter, Kind)`, `Correction(OldSegment, NewSegment, FirstIndex, CorrectedWords)`,
  `Generation`, `MaxCorrectionLength = 200`, `LockedLang`.
- [x] 2.2 Implement `Reset`, `Record(keys, shownText, spacesAfter, kind, ifGeneration?)`, `NoteExtraSpace`,
  `Correction(toLang, layoutId, render)` (render via injected `Func`), and `Confirm(correction, ifGeneration)` —
  faithful to the macOS `PhraseTracker.swift` (drop stale generations; reset if the phrase changed shape).
- [x] 2.3 Correction builder: span from first `Defaulted(other-lang)` word through the last word; re-render
  defaulted words, reproduce neutral/locked verbatim, reproduce spaces from `SpacesAfter`; return null on a
  conflicting lock, a failed re-render, or over the length cap.

## 3. App: abort-safe TextRewriter (prerequisite)

- [x] 3.1 Add a shared abort flag owned by `KeyboardMonitor`: set it on any real (non-injected) keystroke while
  a rewrite is armed; expose arm/disarm + a `ShouldAbort` check to the engine/rewriter.
- [x] 3.2 `TextRewriter.Rewrite`: check the abort flag between injected characters; on abort, re-insert the
  already-erased characters (from the erase count + the text being replaced) and return a new `Result.Aborted`.
- [x] 3.3 `Engine`: arm the guard around every rewrite; treat `Aborted` as "did not happen" — no phrase record,
  reset the tracker, leave layout unchanged.

## 4. App: phrase orchestration in Engine

- [x] 4.1 Hold a `PhraseTracker` in `Engine`; construct its render `Func` from `NWayResolver.Render`.
- [x] 4.2 Rewrite `AutoConvert` to use `Evaluate`: handle `Keep` (record neutral with rendered-current text),
  `Convert` (single word; if the phrase has defaulted-other words and no conflicting lock, build + apply a
  segment correction as one rewrite), and `Ambiguous` (target = lock ?? setting; convert one word, record
  `Defaulted`; `"off"`/no-match → keep).
- [x] 4.3 Record each evaluated word only after a successful rewrite, with the generation captured; commit
  corrections via `Confirm`; skip corrections over the 200-char cap (log, convert current word only).
- [x] 4.4 Reset the phrase when the boundary is Enter/Tab (after processing the word).

## 5. App: KeyboardMonitor reset + spaces

- [x] 5.1 Add a `PhraseReset` event fired from `ClearBuffer` (mouse click / app switch) and the arrow/`Reset`
  key case; also fire it on a backspace that deletes into a previous word (empty current buffer).
- [x] 5.2 Note extra spaces (a boundary space with no pending word) so segment character math stays exact.
- [x] 5.3 In `Engine`, marshal `PhraseReset` through the `_work` queue so all tracker mutation stays on the worker thread.

## 6. Settings + UI

- [x] 6.1 `SettingsManager`: add `AmbiguousLang` (string, default `"uk"`; `"ru"`/`"off"`), persisted; read live.
- [x] 6.2 `SettingsForm` Auto-fix tab: labeled popup (Українська / Русский / Do not convert) mapped by value, applied on Save.
- [x] 6.3 Regenerate `Loc.cs` to include the ambiguity-setting strings from the macOS `Localization.swift`
  (label + option names), falling back to English.
- [x] 6.4 `NWayResolver.ManualPlan`: use `Evaluate`; on `Ambiguous`, promote the preferred-language winner
  (per the setting, injected) to the front of the candidate list.

## 7. Tests + verification

- [x] 7.1 Core tests: `Evaluate` returns `Ambiguous` for an uk/ru word, `Convert` for a single winner, `Keep`
  for valid/none; punctuation core still handled.
- [x] 7.2 Core tests: `PhraseTracker` — defaulted word recorded; single-language word builds the correct
  correction segment; contradictory lock returns null; reset/generation drops stale records; length cap respected.
- [x] 7.3 Build the App; run the self-test; manually verify «добре» converts to uk, a following ru-only word
  re-converts the segment, «там» in a ru phrase stays ru, and concurrent typing aborts cleanly.
- [x] 7.4 Confirm `docs/user-guide*.md` auto-fix section reads platform-neutrally (it compiles into Windows Help).

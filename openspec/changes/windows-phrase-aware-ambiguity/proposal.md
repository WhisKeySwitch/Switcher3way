# Windows Phrase-Aware Ambiguity Resolution

## Why

macOS shipped phrase-aware ambiguity resolution in v1.2.0, but the Windows port
(`Switcher3way.Core` / `NWayResolver.cs`) still uses the pre-1.2 logic: an uk/ru-ambiguous word
(«добре», «там») typed in the wrong layout is left as Latin gibberish because `Resolve` collapses
any two-or-more-winner outcome to `null`. In practice this leaves the most common words unconverted
while the rest of a phrase converts fine — the exact behavior gap the macOS change fixed. The
platform-neutral specs already mandate the corrected behavior (`automatic-conversion-on-word-boundaries`),
so the Windows build is currently out of spec. This change brings Windows to parity.

## What Changes

- **Ambiguity default (Windows).** `NWayResolver` gains an `Evaluate` method returning
  `Keep / Convert / Ambiguous(winners)`. The auto path converts an ambiguous word to the *preferred
  ambiguity language* (new setting, default Ukrainian) instead of leaving it; `"off"` preserves
  today's keep behavior.
- **Phrase tracking (Windows).** A new `PhraseTracker` (in `Switcher3way.Core`, unit-testable)
  records the words typed since the last hard reset (Enter/Tab/arrows/click/app switch — the same
  events that already reset the word buffer) with their keys, on-screen text, trailing spaces, and
  classification (defaulted / locked / neutral).
- **Phrase-level correction (Windows).** When a word valid in exactly one language arrives and the
  phrase holds words defaulted to a *different* language (with no conflicting lock), the defaulted
  words are re-rendered into the new language and replaced in one segment retype, switching the
  layout there. Contradictory phrases (uk-only then ru-only) are left alone — precision-first.
- **Abort-safe segment retype (Windows).** `TextRewriter` becomes abortable: a real keystroke
  arriving mid-rewrite aborts the injection and restores any already-erased characters, so a longer
  multi-word correction can never leave the text half-deleted. This satisfies the existing
  platform-neutral "Abort conversion when the user keeps typing" requirement on Windows.
- **Setting + UI.** New `AmbiguousLang` setting (`uk` default / `ru` / `off`), surfaced as a popup on
  the Auto-fix tab of the Windows Settings window, taking effect without a restart. Manual-trigger
  ordering promotes the preferred-language candidate to the front under ambiguity, matching macOS.

## Capabilities

### New Capabilities

_None._

### Modified Capabilities

- `windows-platform-support`: the N-way detection requirement no longer "leaves ambiguous input
  unchanged" — it resolves ambiguity to the preferred/locked language and self-corrects phrases;
  the rewrite requirement gains abort-and-restore for concurrent typing; the manual-conversion
  requirement offers the preferred language first under ambiguity.

## Impact

- `windows/src/Switcher3way.Core/NWayResolver.cs` — add `Evaluate(keys, capsLock) -> Outcome`
  (`Keep`/`Convert`/`Ambiguous`), `Winner`, and `Render(keys, layoutId)` / `RenderCurrent(keys)`
  helpers; `Resolve` becomes a thin `.Convert`-only wrapper (manual path unchanged in signature).
- `windows/src/Switcher3way.Core/Types.cs` — add `Winner` and the `Outcome` result type.
- `windows/src/Switcher3way.Core/PhraseTracker.cs` (new) — phrase word history, lock state,
  correction plan builder, generation counter for stale-drop.
- `windows/src/Switcher3way.App/Engine.cs` — `AutoConvert` consults the tracker; ambiguous →
  preferred/locked; single-language word triggers a one-shot segment correction via the abortable
  rewriter; reset the phrase on hard boundaries.
- `windows/src/Switcher3way.App/KeyboardMonitor.cs` — a `PhraseReset` signal on the existing
  full-reset events, and an extra-space note; expose the reset hook to the engine (marshaled through
  the worker queue so the tracker stays single-threaded).
- `windows/src/Switcher3way.App/TextRewriter.cs` — abort-on-concurrent-typing + restore-erased.
- `windows/src/Switcher3way.App/SettingsManager.cs` (`AmbiguousLang`), `SettingsForm.cs` (Auto-fix
  popup), `Loc.cs` (regenerated with the ambiguity-setting strings from the macOS `Localization.swift`).
- `windows/tests/*` — Core tests for `Evaluate` ambiguity and `PhraseTracker` correction/lock/reset.
- `docs/user-guide*.md` — the auto-fix section already documents the behavior; verify it reads
  platform-neutrally (it compiles into the Windows in-app Help).

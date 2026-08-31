# Proposal: rescue-wrong-layout-gibberish

## Why

Words no dictionary knows are invisible to the resolver in **both** directions. Ukrainian/Russian
tech jargon typed in the English layout stays as gibberish (`fgrf` instead of `апка`, `nj fqlі
ntyfyne` instead of `то айді тенанту`), and English proper nouns typed in a Cyrillic layout stay
as gibberish too (`Лншм` instead of `Kyiv` — NSSpellChecker doesn't know `Kyiv` either). The
resolver's rule — convert only to a language that *validates* the word — is exactly right for
dictionary words and exactly wrong for jargon and names, which validate nowhere. Every such word
costs a manual selection-convert (all four cases above are from one real user log, 2026-08-27).

The missed signal: these words are not merely "unknown" — the typed rendering is not
*pronounceable* as a word of the typed language, while exactly one candidate rendering is a
perfectly plausible word shape in its language. That asymmetry is checkable, and it is what a
human uses to spot these instantly.

## What Changes

- **A direction-agnostic gibberish-rescue outcome in `NWayResolver.evaluate`**: when a word
  validates in **no** installed language, the resolver asks before keeping it:
  1. Is the typed rendering **gibberish in the typed language** — fails dictionary, fails
     `TypoGuard.nearMiss` (no word one edit away, so it is not a typo), and fails a
     pronounceability check (word-shape heuristic: vowel presence, consonant-run cap)?
  2. Which candidate renderings are **plausible** by the same check in their languages?
- **Target selection mirrors the dictionary path**: exactly one plausible candidate → convert
  to it (covers `Лншм`→`Kyiv`, where only English is plausible); the plausible set is the
  ru/uk pair → convert to the existing **ambiguity-preference language** (Auto-fix setting,
  default uk; "off" keeps, same contract as ambiguous dictionary words — covers
  `fgrf`→`апка`); plausible candidates across scripts with no unique winner → keep, logged.
- **Precision-first guardrails, unchanged and extended**: all existing soft gates (length,
  all-caps, camelCase, mixed-script) still veto first — `Kyiv` typed *in* the English layout,
  `PeopleOps`, `SSO`, code identifiers, and vowel-less Cyrillic abbreviations (`хз`, `кст`)
  must keep exactly as today. The pronounceability thresholds are **measured, not asserted**,
  following the `stop-converting-typos` precedent: a fixture of real must-keep tokens in both
  scripts and real must-rescue jargon decides the heuristic, and zero false conversions on the
  keep side gates shipping.
- **Every decision logs its reason** (`nway: rescue → …` / decline reasons), because this
  path acts exactly where today's log shows silence or a bare keep.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `automatic-conversion-on-word-boundaries`: the "no valid target language → keep" behavior
  gains a measured exception — a word invalid everywhere whose typed rendering is gibberish in
  the typed language SHALL convert to the single plausible candidate language (or to the
  ambiguity default when the plausible pair is ru/uk); tokens plausible in the typed language
  SHALL keep as today.

## Impact

- `Sources/Switcher3wCore/NWayResolver.swift` — the rescue branch in `evaluate`.
- New word-shape plausibility heuristic in `Sources/Switcher3wCore/` (used on both sides of
  the asymmetry check); wired through a `vowels(_:)` sibling of
  `DictionaryValidating.alphabet(_:)` so it stays testable without AppKit.
- `Tests/Switcher3wCoreTests/` — measurement fixture (must-keep tokens in both scripts vs
  must-rescue jargon/names) plus evaluate-outcome cases; the fixture's numbers go into
  `design.md`.
- `Sources/Switcher3w/AppDelegate.swift` — log lines only; the outcome plumbs through existing
  paths.
- Docs: `docs/user-guide*.md` (the ambiguity-preference setting now also governs the Cyrillic
  side of jargon rescue), CLAUDE.md current-state note.
- **Windows port — in scope**: `windows/src/Switcher3way.Core/` (resolver + plausibility
  check) and `windows/tests/Switcher3way.Core.Tests` (fixture re-measured against the Windows
  dictionaries, `TypingSimulationTests` regression). Core is platform-free, so this is
  implemented and measured on the same machine; only the end-to-end verification on the
  installed app belongs to the Windows machine.

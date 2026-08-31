# Design: rescue-wrong-layout-gibberish

## Context

`NWayResolver.evaluate` (Switcher3wCore) currently ends the no-winners path with
`keep — not a word in any installed language`. Everything this change needs is already in
scope there: the typed rendering, every candidate rendering, `TypoGuard.nearMiss`, the soft
gates, and the ambiguity-preference language. The core is Foundation-only and testable off-Mac;
platform services arrive through `DictionaryValidating` / `LayoutCatalog`, and
`DictionaryValidating.alphabet(_:)` already exposes per-language alphabets. Precision is the
project's hard constraint and thresholds must come from measurement
(see `openspec/changes/archive/2026-08-23-stop-converting-typos`).

## Goals / Non-Goals

**Goals:**
- Rescue wrong-layout jargon and names in **either direction** (`fgrf`→`апка`,
  `Лншм`→`Kyiv`) in the shared decision core, gated by a measured, two-sided plausibility
  check.
- Zero regressions on the keep side: every token the fixture marks keep-worthy must still
  keep — in both scripts.
- Full observability: every rescue and every declined rescue logs its reason.

**Non-Goals:**
- Windows *on-device verification* — the Core port and its measurements are in scope (the
  Core test suite runs on this Mac via `DOTNET_ROLL_FORWARD=Major`); typing against the
  installed app is the Windows machine's task. Thresholds are re-measured per platform, never
  copied, because the dictionaries differ.
- Any new user-facing setting — the existing ambiguity preference governs the ru/uk-ambiguous
  case, and nothing else is configurable.
- Rescuing typos (near-miss words stay protected; that battle was just won).

## Decisions

**D1 — The rescue lives in the no-winners branch of `evaluate`, after every existing veto.**
Order: soft gates → dictionary winners (none) → typed-language near-miss check → asymmetric
plausibility → target selection → rescue. Rationale: rescue must be the *last resort*, so
every existing precision mechanism keeps its authority. Alternative — a parallel pre-pass —
rejected: it would need its own gate duplication and could shadow dictionary decisions.

**D2 — Plausibility is a structural word-shape check, not a language model.** Per language:
(a) contains at least one vowel of that alphabet, (b) longest consonant run ≤ N,
(c) no bigrams from a small impossible-bigram list. Start with (a)+(b) and let the fixture
say whether (c) is needed. Rationale: `fgrf`, `ljpdjktyt`, `Лншм` all fail on vowels alone;
the check is symmetric, Foundation-only, portable to the Windows core, and explainable in a
log line. Alternative — bigram frequency tables trained from the dictionaries — rejected for
v1: heavier, opaque, and the fixture can promote it later if structural rules measure short.
The vowel sets ride a `vowels(_:)` sibling of the existing `alphabet(_:)` injection point
(defaulting to `""` = check disabled, same fail-open convention). English counts `y` as a
vowel (`gym`, `Nyx`).

**D3 — Both sides must agree (the asymmetry), direction-agnostically.** The typed rendering
must FAIL plausibility in the typed language; the candidate set is whichever renderings PASS
it in theirs. One-sided checks are not enough: `npm`/`zsh` fail English plausibility but
their Cyrillic renderings fail too → keep; `Kyiv` typed in the English layout passes English
plausibility → keep regardless of the Cyrillic side; `кст` typed in a Cyrillic layout fails
Cyrillic but its Latin rendering (`rcn`) fails English → keep.

**D4 — Target selection mirrors the dictionary path.** Exactly one plausible candidate →
convert to it (this is the `Лншм`→`Kyiv` case — English wins because it is the only
plausible shape, and the ambiguity preference is irrelevant). Plausible set = the ru/uk pair
→ the ambiguity-preference language (off → keep, the setting's existing contract). Plausible
candidates across scripts with no unique winner → keep, logged as an ambiguous rescue — a
wrong pick here costs a sentence, a keep costs one trigger tap. Alternative — always prefer
the typed-script's opposite — rejected: it invents a heuristic the dictionary path doesn't
have.

**D5 — Rescue length floor, measured, expected around 4.** The held rule (<6 needs the phrase)
exists because short dictionary words carry little evidence; a rescue candidate carries even
less, but the motivating cases (`апка`, `айді`, `Лншм`) are 4 letters. The floor also carries
the short-abbreviation risk on the Cyrillic side (`пн`→`gy` would pass the vowel check at
length 2). The floor is a fixture-derived number, not 6 by inheritance and not 2 by optimism.
Below the floor: keep (unchanged behavior).

**D6 — A rescued word enters the phrase as a defaulted word.** Same status as an ambiguous
word converted by preference: if a later word locks the phrase to the other Cyrillic language,
`PhraseTracker` retro-corrects it; the manual trigger cycles it back like any conversion.
Rationale: the rescue borrows the ambiguity-preference contract wholesale — one mental model.
A unique-winner rescue (`Kyiv`) participates the same way; retro-correction across scripts
already has no path, so nothing new to guard.

**Measured (macOS, 2026-08-27, real NSSpellChecker en+uk+ru):** keep side **0/22 false
conversions** (19 English tokens incl. `ctrl`/`http`/`html`/`kyiv`/`emergancy`, 3 Ukrainian);
rescue recall **latin→cyrillic 4/5 (0.80)** — the miss is `fqls`→`айді`, vetoed by the typo
guard because `fils` is one edit away in English, which is the guard's contract working —
**cyrillic→latin 2/2 (1.00)**. Constants that produced this: `rescueFloor = 4`,
`maxConsonantRun = 4`, vowel sets with English `y`, the impossible-onset list, and the
known-token list (`ctrl`, `http`, …) in `WordShape`.

**Measured (Windows Core, 2026-08-27, bundled Hunspell en+uk+ru, run on macOS via
`DOTNET_ROLL_FORWARD=Major`):** keep side **0/28 false conversions**; rescue recall
**latin→cyrillic 5/5 (1.00)** — Hunspell does not know `fils`, so the near-miss veto that costs
macOS the `fqls`→`айді` case does not fire — **cyrillic→latin 2/2 (1.00)**. Same constants as
macOS (`RescueFloor = 4`, `MaxConsonantRun = 4`, onset + known-token lists in `WordShape`);
the full suite (191 tests, `TypingSimulationTests` paragraph precision included) stays green.

**D7 — Measurement is a unit test, and it gates by construction.** A fixture file — keep-side:
proper nouns, acronyms, identifiers, brand names incl. vowel-less ones, `y`-vowel names,
real English typos, Cyrillic vowel-less abbreviations (`хз`, `кст`, `пн`); rescue-side: the
log's jargon (`апка`, `айді`, `тенанту`, `чекнути`, `Кашир`) plus `Лншм`→`Kyiv`-style
reverse cases — with a test asserting **zero** keep-side conversions and reporting
rescue-side recall per direction. Threshold constants live next to `nearMissTrustedFrom`
with the fixture numbers in a comment. The dictionary-quality test pattern
(`WordFixture.swift`) already shows how to keep this runnable off-Mac.

## Risks / Trade-offs

- [Vowel-based rules are crude for very short words — almost any 2–3-letter cluster can be a
  legit abbreviation in either script] → the length floor (D5) plus soft gates carry short
  tokens; below the floor nothing changes.
- [English tokens with no vowels that are real (`npm`, `zsh`, `pwd`)] → two-sided check (D3):
  their Cyrillic renderings are also vowel-less gibberish, so they keep.
- [Cyrillic-side false rescues: a legit vowel-less Cyrillic abbreviation whose Latin rendering
  happens to look English] → fixture must hunt for these explicitly; the length floor and the
  keep-side zero-tolerance gate decide whether the Cyrillic→English direction ships at the
  same floor or a higher one per direction.
- [A rescue lands in a phrase that later proves Russian] → D6, retro-correction already
  handles the identical case for ambiguous words.
- [User disagrees with a rescue] → the conversion chip + trigger-undo + learn-from-undo
  ("Never convert" offer) all apply unchanged; the log names the rescue explicitly.

## Migration Plan

Ships inside existing contracts (auto-convert master toggle; ambiguity preference for the
ru/uk case), so no new setting, no defaults migration. Rollback = revert the resolver commit;
no persisted state. Docs: user-guide (three languages) gets one paragraph under the ambiguity
setting; CLAUDE.md current-state note.

## Open Questions

- Whether an impossible-bigram list (D2c) earns its place — the fixture decides; deferrable
  because it only tightens the same injection point.
- Whether the length floor needs to differ per direction (Latin→Cyrillic vs Cyrillic→Latin) —
  the fixture decides; the spec only promises measured floors.
- Whether the rescue should also fire when the typed rendering is within one edit of a word
  of a *candidate* language (a typo'd jargon word) — deferrable; today's behavior (keep) is
  the safe default and the spec doesn't promise it.

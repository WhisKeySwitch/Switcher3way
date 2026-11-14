# Design: quarantine-a-lying-dictionary

## Context

`NWayResolver.evaluate` computes each candidate's validity once while building the per-language
candidate list, then re-queries the dictionary in the winners loop. `Dict` (macOS) is a thin
`NSSpellChecker.shared` wrapper; the checker demonstrably goes through transient episodes of
answering wrong in both directions (log evidence 2026-07-20…08-31; reproduced in a test-suite
run). The repo already documents the checker's back-to-back inconsistency in
`DictionaryQualityTests`. A standalone probe of 200 interleaved queries could NOT reproduce the
flake in a fresh process — the bad states are session/episodic, so the fix must be defensive,
not a one-line configuration.

## Goals / Non-Goals

**Goals:**
- A decision can never contradict its own log line.
- A lying dictionary results in *no* conversions for that language, never *wrong* ones —
  and the episode is visible in the log, with automatic recovery.

**Non-Goals:**
- Fixing `NSSpellChecker` itself, or diagnosing why the episodes happen.
- A sentinel on Windows — Hunspell runs in-process on bundled files and is deterministic; only
  the single-verdict cleanup ports (parity, and one fewer query per word).
- New settings. Reliability is not a preference.

## Decisions

**D1 — Single verdict: the winners loop reuses `Candidate.isValid`.** The candidate list already
carries the answer; asking again bought nothing except the chance to disagree with it. Trade-off
made explicit: the accidental double-query acted as an AND of two flaky samples, which sometimes
*suppressed* false-valid episodes (`Тфефдшу VALID` never converted). That protection was luck,
not design; D2 replaces it with a deliberate mechanism.

**D2 — A canary sentinel as a core-level decorator, not adapter logic.** `DictionarySentinel`
wraps any `DictionaryValidating`; per language it probes on first use and then at most once per
`probeInterval` (60 s), off the per-keystroke path. Canaries per language are injected by the
executable (`привіт`/`нзукжз` for uk, `привет` for ru, `the` for en; mash shared). A failed
probe quarantines: `isAvailable(lang) == false` until a probe passes after `cooldown` (60 s).
The resolver already treats unavailable languages as nonexistent — no resolver changes needed
for the quarantine to bite, and the current language being quarantined degrades to
`keep(.noCurrentLanguage)`, i.e. do nothing. Clock is injected (`now: () -> Date`) so tests
drive time. Alternative — majority-of-three per query — rejected: triples the hot-path cost and
still trusts a sustained bad episode, which is exactly what the log shows.

**D3 — `automaticallyIdentifiesLanguages = false` on the shared checker.** Every query names its
language; the checker's own language-guessing state is the one stateful input we can remove
outright. Not proven to be the trigger (the probe passed 200/200 both ways in a fresh process),
but it is the documented-correct configuration for explicit-language checking and costs nothing.

**D5 — Verify before acting, not only on a timer.** Field evidence settles a question the
periodic probe cannot: `тфефдшу` and `ішпщгктун` (logged as `uk VALID` on 2026-08-07) are
correctly REJECTED today, five rounds running — so those were transient false-valids, not a weak
dictionary. Which means the dangerous direction is live: during such an episode, and with the
double-query removed by D1, `Natalie` would convert to `Тфефдшу` and take the layout. Any interval
between probes is a window for that, so `verifyTrust(lang)` is asked immediately before acting on
dictionary evidence and re-probes when its verdict is older than `actFreshness` (2 s). Conversions
are rare next to keystrokes, so this costs two dictionary queries a few times a minute; the
per-word path is untouched. Ported to the Windows core, where the default `true` keeps Hunspell's
behavior unchanged.

**D4 — Quarantine logs are unconditional.** `logAlways`-grade via a dedicated CoreLog prefix:
a suspended dictionary is the app silently "not working" from the user's chair, which is
exactly the class of failure the debug-log gate must not hide.

## Risks / Trade-offs

- [False-valid episode shorter than `probeInterval` slips through and converts wrongly] → closed
  by D5: the probe is re-taken at the moment of acting, so the exposure is `actFreshness` (2 s)
  rather than `probeInterval`.
- [Canary word missing from a user's dictionary variant (`привіт` should be safe)] → a language
  stuck quarantined logs loudly on every probe; the canary is a constant next to the wiring.
- [Losing the accidental AND-of-two-samples precision] → D2's mash canary catches accept-all
  episodes explicitly, and D5 asks it again at the moment of acting, which is strictly stronger
  than the old accident; the fixture keep-side gates (rescue change) stay green.

## Migration Plan

No settings, no persisted state. Rollback = revert. Windows ships the single-verdict cleanup
with its next release; no behavior change expected there (Hunspell deterministic) — the
`TypingSimulationTests` stay the gate.

## Open Questions

- Whether the probe should also cover `alphabet`/`vowels` health — deferrable: both are static
  per language and not oracle-dependent.

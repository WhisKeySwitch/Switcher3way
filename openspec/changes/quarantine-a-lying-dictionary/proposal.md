# Proposal: quarantine-a-lying-dictionary

## Why

A whole line typed in the wrong layout went unconverted (user report, 2026-08-31), and the log
shows the impossible: `nway: nil — no valid target language [… uk:'відгуки' VALID]` — the dump
says the Ukrainian candidate is a valid word, the verdict says no language validates it. Fourteen
such self-contradictory lines exist in the log since July, including plain `Привіт!`, `Дякую!`,
`хто`, `ти`. The cause is two-fold: `NWayResolver` asks the dictionary about the same word
**twice** per evaluation (once building candidates, once picking winners), and `NSSpellChecker`
goes through transient bad episodes where it answers wrong — in both directions: real words
rejected, and keyboard mash accepted (`uk:'Тфефдшу' VALID`). The same pathology reproduced
independently in the test suite (a full-suite run where the uk dictionary rejected every fixture
word and accepted every mash line, passing in isolation minutes later).

An oracle that lies sometimes cannot be trusted blindly by a precision-first app: a false
"invalid" silently eats conversions; a false "valid" converts a name into Cyrillic noise.

## What Changes

- **One verdict per word per evaluation.** The winners loop reuses the validity computed when
  the candidate was built instead of asking again, so the outcome can never contradict the
  logged dump. Ported to the Windows core for parity (Hunspell is deterministic, so there it is
  a cleanup, not a fix).
- **A canary sentinel around the macOS dictionary.** A core-level decorator
  (`DictionarySentinel`) probes each language with two canaries — a word that must validate
  (`привіт`) and mash that must not (`нзукжз`) — on first use and periodically after. A failed
  probe **quarantines the language**: it reports as unavailable, so the resolver simply cannot
  produce winners (or rescues) from a lying dictionary, and auto-conversion degrades to doing
  nothing rather than doing wrong. Re-probed after a cooldown; recovery is automatic. Every
  quarantine and recovery is logged loudly (`logAlways`-grade — the user can never report this
  otherwise).
- **The spellchecker stops guessing languages.** `NSSpellChecker.automaticallyIdentifiesLanguages`
  is switched off — every query names its language explicitly, and the shared checker's
  language-detection state has no business influencing the answers.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `layout-switching-and-language-detection`: dictionary validation gains a reliability
  contract — one verdict per word per decision, and a language whose dictionary fails a
  known-word/known-mash probe SHALL be excluded from detection until it recovers.

## Impact

- `Sources/Switcher3wCore/NWayResolver.swift` — winners loop reuses the candidate verdict.
- `Sources/Switcher3wCore/DictionarySentinel.swift` — new decorator (Foundation-only, injectable
  clock, testable with lying fakes).
- `Sources/Switcher3w/CoreAdapters.swift` + `AutoSwitch.swift` — wrap `SystemDictionary` in the
  sentinel; `automaticallyIdentifiesLanguages = false`.
- `windows/src/Switcher3way.Core/NWayResolver.cs` — same single-verdict cleanup (no sentinel:
  Hunspell is in-process and deterministic).
- Tests: sentinel behavior with honest/accept-all/reject-all fakes incl. recovery; a resolver
  test with a flip-flopping fake proving the outcome follows the first verdict.

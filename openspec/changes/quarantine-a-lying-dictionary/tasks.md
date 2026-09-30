# Tasks: quarantine-a-lying-dictionary

## 1. Single verdict per decision

- [x] 1.1 macOS: winners loop in `NWayResolver.evaluate` reuses `Candidate.isValid` instead of
      re-querying the dictionary
- [x] 1.2 Windows: same cleanup in `NWayResolver.cs` (parity; no behavior change expected)
- [x] 1.3 Test: a flip-flopping fake (valid on first query for a word, invalid after) — the
      outcome must follow the first verdict and match the dump

## 2. The sentinel

- [x] 2.1 `DictionarySentinel` decorator in Switcher3wCore: injected canaries per language,
      probe on first use + at most once per `probeInterval` off the hot path, quarantine on
      failure (`isAvailable == false`), automatic recovery after `cooldown`, injected clock
- [x] 2.2 Unconditional logging of quarantine and recovery (CoreLog; the executable's sink
      routes it to `logAlways`)
- [x] 2.3 Tests: honest fake untouched; accept-all fake quarantined via the mash canary;
      reject-all fake quarantined via the word canary; recovery when the fake heals after the
      cooldown; probes do not run per-query

## 3. Wiring

- [x] 3.1 `NWay.resolver` wraps `SystemDictionary` in the sentinel with canaries
      (en `the`, uk `привіт`, ru `привет`; mash `нзукжз`/`zzqxj`)
- [x] 3.2 `Dict`: set `automaticallyIdentifiesLanguages = false` once at startup
- [x] 3.3 `swift test` and `dotnet test` green; `openspec validate` green

## 4. Verify

- [~] 4.1 (in progress — shipped in 1.5.1, watching the log) Run the app with debug log through a normal day; confirm no self-contradictory
      `VALID`-but-kept lines appear, and any quarantine episodes log with recovery

## 5. Quarantine must not hand the word to the sibling (2026-09-24)

- [x] 5.1 Field log 2026-09-16..24: six `Вітаю`/`Привіт`/`Вирішено` → Russian misspellings and
      seven unopposed ru conversions of uk/ru shared words, all inside uk quarantine windows;
      the ambiguity preference (uk) was never consulted because uk was not a candidate
- [x] 5.2 `DictionaryValidating.isQuarantined` (default false; sentinel implements) so the
      resolver can tell "installed but lying" from "not installed"
- [x] 5.3 `NWayResolver.evaluate`: quarantined languages stay in `byLang` as untrusted
      candidates; a word-shaped untrusted rendering contests a sibling win (keep,
      `.dictionaryUntrusted`) unless the phrase backs the winner; typing in the quarantined
      language keeps with the quarantine named; the rescue sees the candidate by shape
- [x] 5.4 `QuarantinedCandidateTests` (7 cases) — the `Вітаю`/`тебе` field cases, phrase override,
      shapeless renders not contesting, healthy path unchanged; `swift test` 130 green


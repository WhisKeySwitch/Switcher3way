# Tasks: rescue-wrong-layout-gibberish

## 1. Measurement first (the numbers gate everything)

- [x] 1.1 Build the fixture, both directions: keep-side tokens (proper nouns and acronyms
      typed in their own layout, identifiers, brand names incl. vowel-less ones like
      `npm`/`zsh`, `y`-vowel names, real English typos, Cyrillic vowel-less abbreviations
      `хз`/`кст`/`пн`) and rescue-side tokens (the 2026-08-27 log jargon — `апка`, `айді`,
      `тенанту`, `чекнути`, `Кашир` — plus reverse cases like `Лншм`→`Kyiv` and a collected
      jargon/names list), each with its wrong-layout rendering
- [x] 1.2 Implement the word-shape plausibility check (vowel presence + consonant-run cap,
      per-language vowel sets via a `vowels(_:)` injection point defaulting to disabled;
      English vowels include `y`)
- [x] 1.3 Write the measurement test: assert zero keep-side conversions, report rescue-side
      recall per direction; iterate the heuristic (consonant-run N, length floor(s), optional
      impossible-bigram list) until the keep side is clean — record the final numbers in
      design.md

## 2. Resolver

- [x] 2.1 Add the rescue branch to `NWayResolver.evaluate`'s no-winners path: typed-language
      near-miss veto → asymmetric plausibility (typed fails, candidates pass) → length floor
- [x] 2.2 Target selection: unique plausible candidate converts outright; ru/uk pair goes to
      the ambiguity-preference language (off = keep); cross-script tie keeps, logged
- [x] 2.3 Mark the rescued word as a defaulted word in the phrase (retro-correction eligible
      for the ru/uk case), and make the manual trigger cycle it back exactly like other
      conversions
- [x] 2.4 Log every outcome: `nway: rescue → <lang>` with both renderings, and the decline
      reasons (`plausible in typed language`, `no plausible target`, `cross-script tie`,
      `below length floor`)

## 3. App wiring & docs

- [x] 3.1 Wire the vowel sets in `CoreAdapters.swift` (`SystemDictionary`) for en/ru/uk
- [x] 3.2 Extend evaluate-outcome tests in `Tests/Switcher3wCoreTests` with the spec's seven
      scenarios (both rescue directions, plausible-keep, both-sides-gibberish keep, soft-gate
      veto, preference-off split, manual reversal)
- [x] 3.3 User guide (en/uk/ru): one paragraph under the ambiguity-language setting explaining
      jargon rescue in both directions; CLAUDE.md current-state note
- [x] 3.4 `swift test` green; `openspec validate` green

## 4. Windows Core port (implemented on this Mac — Core is platform-free and its tests run here)

- [x] 4.1 Port the plausibility check and rescue branch to
      `windows/src/Switcher3way.Core/NWayResolver.cs` (+ `SoftGates`/`Interfaces` as needed),
      mirroring the macOS decisions: near-miss veto first, asymmetric plausibility, unique
      winner / ru-uk-pair-to-preference / cross-script-tie-keeps, length floor
- [x] 4.2 Port the fixture and measurement test to `windows/tests/Switcher3way.Core.Tests`;
      thresholds re-measured against the Windows dictionaries, not copied — record numbers
      alongside the macOS ones in design.md
- [x] 4.3 Score the rescue over `TypingSimulationTests` paragraphs — whole-text precision must
      not regress (`DOTNET_ROLL_FORWARD=Major dotnet test windows/tests/Switcher3way.Core.Tests`
      on this Mac)
- [x] 4.4 Check whether `Engine.cs` needs to route the new outcome or reuses Convert unchanged;
      wire logging of rescue reasons

## 5. Verify on the machines that hurt

- [x] 5.1 macOS: install the build on the Teams-heavy Mac, enable debug log, type the
      motivating phrases (`fgrf`, `nj fqlі ntyfyne`, and `Kyiv` while in a Cyrillic layout)
      and confirm rescue lines + conversions land
      — verified by the user on a 1.5.0 pre-release build, 2026-08-29 ("seem to work fine")
- [x] 5.2 macOS: type the keep-side sentinels (`Kyiv` in the English layout, `PeopleOps`,
      `SSO`, `npm`, `хз`) in normal text and confirm keeps with logged reasons
- [x] 5.3 **Windows:** end-to-end on a packaged build, through
      `windows/tools/verify-typo-guard.py` extended with a rescue phase. Every motivating word
      converted and every keep-side sentinel kept — **zero false conversions**:

      ```
      auto: "fgrf"    -> "апка"  [uk]      auto: "хз"        kept
      auto: "nj"      -> "то"    [uk]      auto: "Kyiv"      kept
      auto: "fqls"    -> "айді"  [uk]      auto: "PeopleOps" kept
      auto: "ntyfyne" -> "тенанту" [uk]    auto: "SSO"       kept
      auto: rescue -> [en] — no dictionary knows "Лншм", but only en fits its shape
      auto: "Лншм"    -> "Kyiv" [en]       auto: "npm"       kept
      ```

      **The Windows result differs from the macOS one, and that is the point of having run it.** Only
      `Лншм`→`Kyiv` took the rescue path here. The four Ukrainian jargon words converted through the
      ordinary dictionary route, because the bundled Hunspell dictionaries know `апка`, `айді` and
      `тенанту` where macOS's `NSSpellChecker` does not. So on Windows the rescue earns its place for
      the *other* direction — English names typed in a Cyrillic layout, which no dictionary on either
      platform covers. Ticking this from the macOS run would have recorded a rescue that never fired.

      The caret chip appears on the rescued word (`chip: caret screen=…`), which is the visible undo
      affordance, and the cancel cycle is seeded by the same `ConvertSingle` path the dictionary
      conversions use. **The trigger itself remains unscriptable** — the app swallows it as a control
      key — so the undo keystroke is confirmed by construction rather than by test, as it is for every
      other conversion.

      Three fixes to the harness were needed to get a trustworthy run, and all three had been silently
      producing wrong answers: it now activates the window it launched (Notepad opened behind a
      browser and the run typed nowhere), refuses to type unless that window has focus, and switches
      layouts by the HKLs the system reports rather than what `LoadKeyboardLayout` returns — Ukrainian
      is installed here as the enhanced variant (`FFFFFFFFF0A80422`), so every earlier layout switch
      had failed silently.

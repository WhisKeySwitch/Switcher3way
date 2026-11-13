# Design

## Context

See proposal.md for why. The state this design starts from:

- `NWayResolver.evaluate` builds one candidate per language from every enabled layout whose language
  `NSSpellChecker` covers. It already runs over whatever the user enabled, so "combinations" need no
  new plumbing. What is missing is per-language knowledge, and a way to say that a language is not
  ready.
- Per-language knowledge is scattered today. Vowels and canaries sit in `CoreAdapters.swift`, the
  short-word lists sit in `ShortWords.swift`, and the uk/ru pair is hardcoded in the rescue's tie rule
  and in the Settings popup. Every piece fails open for an unknown language. That was right for three
  languages and is the reason German or Bulgarian today get the dictionary alone.
- `resolveAmbiguity` already settles any tie that contains the preferred language, not only uk/ru. So
  the `нещо`→`луна` case was the preference doing what the code says, while the UI presented it as a
  Ukrainian-versus-Russian choice. The defect is in the contract and the UI, not the resolver's
  dictionary path. The rescue path does hardcode the pair (`langs == ["ru", "uk"]`).
- Words end only on Space, and keystrokes are buffered by key position. A layout that puts punctuation
  on letter keys (AZERTY `,` on the US `m` key), or letters on digit keys (AZERTY `é` on `2`), is
  therefore rendered correctly without any boundary change.
- The draft `Tests/Switcher3wCoreTests/BulgarianCostTests.swift` from 2026-09-28 is the starting point
  for the measurement. It hardcodes layout tables and fails two assertions by design, because it
  measured Bulgarian on top of en+uk+ru instead of per combination.

## Goals / Non-Goals

**Goals:**

- One place in the core that states what the app knows about each language, and treats absence as
  "not supported" rather than "fail open".
- A measurement that walks every two- and three-language combination of the supported set and fails
  when an admitted combination misses the bar.
- Ties between any two same-script languages resolve the same way, on both the dictionary and the
  rescue path.

**Non-Goals:**

- Windows detection of German or French. Windows bundles Hunspell dictionaries and would need licensed
  de/fr dictionaries. The only Windows change is the regenerated short-word file.
- Re-deciding Russian Phonetic and Ukrainian QWERTY. Their numbers are recorded in the proposal; the
  decision belongs to a follow-up, because it takes away auto-fix from people who use it today.
- A priority list of several preferred languages. One preferred language covers every tie in a
  combination of three, since a tie needs at least two languages that are not the one being typed.
- Letting users pick detection languages inside the app. macOS input sources already are that choice.

## Decisions

### 1. A language profile table in the core

`Switcher3wCore` gains `LanguageProfile`: script (Latin or Cyrillic), vowels, canary word and mash,
and whether the language is admitted. The short-word lists stay in `ShortWords.swift`, because the
Windows generator reads that file, but a profile without a list is not admissible.

`SystemDictionary.vowels`, the sentinel's canaries and the Settings popup all read from the table.

*Alternative considered:* keep the knowledge in the app adapter and add rows. Rejected. It keeps the
knowledge untestable without AppKit, and the rescue's tie rule needs the script, which is core logic.

### 2. Unsupported languages are skipped in `evaluate`, not in the catalog

The resolver skips a layout whose language has no admitted profile when building candidates. It also
keeps the layout if it is the current one, then keeps the word with a reason `unsupportedLanguage`, so
typing in an unsupported language moves nothing. `manualPlan` is untouched and still cycles through
every enabled layout. The app logs once per language per session that it was skipped.

*Alternative considered:* filter in `SystemLayoutCatalog.installedLayouts`. Rejected, because the
manual trigger uses the same catalog and must keep offering those layouts.

### 3. Transliteration is detected from the layout, not listed by ID

The app adapter translates the keys `a e i o u` through each layout. A layout of a non-Latin-script
language that yields at least four of its language's vowels is flagged as transliterating. The flag
travels on `Layout`. Measured on macOS 27: ЙЦУКЕН layouts and standard Bulgarian yield one vowel;
Bulgarian Phonetic, Russian Phonetic and Ukrainian QWERTY yield five. Latin-script languages are
never flagged, because for them the question is covered by the combination measurement instead.

`evaluate` does not make a flagged layout a candidate unless it is the current layout or its language
is Russian or Ukrainian. When a language has both a standard and a flagged layout enabled, the
standard one becomes the target.

*Alternative considered:* a list of layout IDs. Rejected, because third-party phonetic layouts would
slip through and every new language would need a manual entry.

### 4. Ties resolve by the preference within one script

`resolveAmbiguity` keeps its logic: the lock wins if it is a candidate, then the preference if it is a
candidate, otherwise nothing. The rescue's tie rule changes from "exactly uk and ru" to "all plausible
candidates share a script", and then defers to the same `resolveAmbiguity`. A cross-script tie in the
rescue keeps, as today.

The dictionary path already emits `.ambiguous` for any tie, including cross-script ones such as
English and German both valid on the French layout. Those are Latin-Latin ties, and the preference
settles them only if the user chose one of those languages. The measurement reports how often each
combination produces a tie and how each resolved.

### 5. The preference setting

`SettingsManager.ambiguousLang` accepts any admitted language code or `off`, and stops normalising
unknown values back to `uk`. The Auto-fix popup lists enabled admitted languages other than English,
in their own names, plus "do not convert". A stored language that is not enabled appears as the
selected item marked unavailable, so opening Settings never rewrites the setting.

### 6. The combination measurement

The draft test becomes `LanguageCombinationTests`:

- **Layout tables are read at run time** from every installed input source (`includeAllInstalled`),
  so the test measures the Mac it runs on. The draft's hardcoded strings go. A language whose layout or
  dictionary is missing is skipped with a printed reason.
- **Default layout per language:** US, Ukrainian-PC, RussianWin, Bulgarian, German, French. Bulgarian
  Phonetic runs as a variant to prove it is not a target.
- **Prose corpora:** the Windows port's en and uk text verbatim, plus new bg, de and fr prose of the
  same kind. Russian gets prose too, since combinations without Ukrainian need it.
- **Per combination:** keep (own prose on own layout, must move nothing), typos (dropped, doubled and
  transposed letters of each language's prose on its own layout), recall (each non-English language
  typed with the English layout active, or English typed on the other layout when English is absent),
  and wrong-text conversions (must be zero).
- **Baseline** is en+uk+ru, measured in the same run, and the typo bar is its worst per-language rate.
- **Gated behind `SWITCHER3W_MEASURE_COMBINATIONS=1`**, because 35 combinations through the real
  spell checker take minutes. A fast test in the normal suite covers the three shipped combinations
  that matter most (en+uk+ru, en+bg, en+de+fr) so regressions are caught on every `swift test`.

### 7. Short-word lists for bg, de, fr

Written the same way as uk/ru: function words, pronouns, particles, and short words that are typed as
themselves. `ShortWordFixture.inProse` gains every word of three letters or fewer from the new prose,
and the existing coverage test fails below 100%. `ShortWords.cs` is regenerated from the Swift file.

### 8. Belarusian waits behind a dictionary gate; Kazakh is recorded, not built

Belarusian needs nothing new from the resolver: its profile is a Cyrillic row with vowels
`аеёіоуыэюя`, a canary and a short-word list, and its ties with Russian and Ukrainian go through
decision 4. The only open question is where its dictionary comes from, and that is decided in order:

1. **Re-test the system route properly.** Install a Hunspell dictionary into `~/Library/Spelling`,
   log out and back in, and enable the language in Keyboard → Text Input → Spelling. The 2026-09-28
   test restarted the spell server only, and that is not the same thing. If `availableLanguages`
   then lists the language and `checkSpelling` rejects mash, the app needs no dictionary code at all:
   `Dict.isAvailable` already admits whatever the system lists.
2. **Otherwise, an in-app Hunspell reader**, loading a dictionary the user downloads from Settings.
   The Windows `HunspellDictionaryValidator` is the reference behaviour. This is a design of its own
   and gets its own change; this change records the need and stops.
3. **Either way, the licence decision comes first** and is written into this change: CC BY-SA 4.0 or
   LGPLv3 for a data file the app downloads or reads but does not ship.

*Alternative considered:* bundle `be_BY` in the app, as the Windows port bundles `uk` and `bg`.
Rejected for the same reason the Windows port rejected it.

Kazakh gets no code. The digit-row requirement is recorded in the proposal so the future change starts
from it.

## Risks / Trade-offs

- [A new language's short-word list misses a common word, and that word is converted away inside a
  phrase settled the other way] → The coverage gate over prose, plus the list-first triage rule the
  handover already documents for "it converted a word I meant".
- [German capitalises every noun, and French uses apostrophes (`l'eau`, `c'est`)] → The soft gates
  already handle leading capitals and contractions. The keep measurement types the prose with its real
  capitals and apostrophes, so a regression shows up as a moved word.
- [Latin-Latin pairs give little to detect, so a quiet log looks like a broken feature] → Recall is
  printed per combination and quoted in the user guide, as the Windows proposal did for Serbian.
- [The measurement depends on which dictionaries this Mac has] → Missing languages are skipped with a
  printed reason, never passed silently. The admission decision records the macOS version measured on.
- [**BREAKING**: someone relying on unmeasured detection for Spanish or Italian loses it] → Auto-fix
  for them was unmeasured, and the manual trigger still works. The skip is logged, and the user guide
  lists the supported languages.
- [The user-installed dictionary route works only after a logout, or only for some users] → Belarusian
  is admitted only after the route is proven on a clean login, and the user guide states the exact
  steps. A language the system does not list stays unsupported, so a half-installed dictionary can
  never make the app treat every string as valid.
- [The measurement takes minutes] → Gated behind an environment variable, with a fast subset in the
  default suite.

## Migration Plan

- Stored `ambiguousLang` values `uk`, `ru` and `off` stay valid; no migration is needed.
- Rolling back is a revert. No new defaults keys are written, and an older build reading a stored
  `bg`, `de` or `fr` preference normalises it back to `uk`, which is today's behaviour.
- Ship in the next macOS minor release, with the regenerated `ShortWords.cs` riding the next
  `windows-v*` tag after `dotnet test` passes.

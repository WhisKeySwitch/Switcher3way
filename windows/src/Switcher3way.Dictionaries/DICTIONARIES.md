# Dictionaries

`HunspellDictionaryValidator` loads `<lang>.dic` + `<lang>.aff` (Hunspell format) from a directory,
one pair per 2-letter language. It uses managed
[`WeCantSpell.Hunspell`](https://www.nuget.org/packages/WeCantSpell.Hunspell) (no native deps), so
validation is fully offline and independent of installed OS language packs. The default constructor
reads the `dict/` folder deployed next to the assembly.

## Bundled dictionaries (in `dict/`)

All three are **free and permissively licensed** — safe to bundle in this MIT app. Each dictionary's
own license text ships alongside it as `<lang>.license`.

| Lang | Source | License | Notes |
|------|--------|---------|-------|
| `en` | [wooorm/dictionaries](https://github.com/wooorm/dictionaries) (SCOWL) | **MIT AND BSD** | `en_US` |
| `ru` | [wooorm/dictionaries](https://github.com/wooorm/dictionaries) (Lebedev/Klukvin) | **BSD-3-Clause** | attribution only |
| `uk` | [LibreOffice/dictionaries `uk_UA`](https://github.com/LibreOffice/dictionaries/tree/master/uk_UA) | **MPL 1.1** | file-level copyleft; keep under MPL |

### Why not `dict_uk` for Ukrainian?
The modern [`brown-uk/dict_uk`](https://github.com/brown-uk/dict_uk) dictionary *data* is
**CC BY-NC-SA 4.0 (NonCommercial)** — not an open license, and incompatible with an MIT app (its
build *software* is GPL-3.0, which is what some repackagers, e.g. wooorm's `uk`, label it). We use
the older **LibreOffice `uk_UA` (MPL 1.1)** lineage instead, which is genuinely free.

## Compliance

- Each `<lang>.license` file stays next to its `.dic`/`.aff`.
- MPL (uk) is file-level copyleft: keep the dictionary files under MPL and unmodified-in-license;
  the MIT app code is unaffected (aggregation of data, not linked code). BSD (ru) and MIT/BSD (en)
  need only attribution.
- `dict/.gitattributes` marks `*.dic`/`*.aff` as binary so line endings stay byte-exact.

## Loading

`new HunspellDictionaryValidator()` → `dict/` next to the assembly. The csproj marks `dict/**` as
`Content` with `CopyToOutputDirectory`, so the files deploy with the app and flow to referencing
projects (the tests load them for the real-dictionary smoke tests).

## Quality baseline (measured 5 August 2026)

The original plan was to diff these against macOS `NSSpellChecker`. That needs a Mac, and it is also
the less useful half of the idea: what matters is not whether Hunspell agrees with Apple but whether it
accepts and rejects the words that decide a conversion. So the baseline is a **checked-in fixture** —
`windows/tests/Switcher3way.Core.Tests/DictionaryQualityTests.cs` — covering both error directions,
because they fail differently:

* a **false reject** (a real word the dictionary does not know) means the fix silently never happens;
* a **false accept** (nonsense the dictionary blesses) is worse — the resolver concludes the input is
  already valid, or valid in two languages, and either skips the fix or corrupts good text.

Measured across 171 words that must be accepted and 38 that must be rejected:

| Set | Result |
|---|---|
| Accept — everyday, 2-letter, inflected nouns/verbs, declined adjectives, ё and ё-omitted spellings, apostrophe forms (`комп'ютер`), loanwords, proper nouns | **170 / 171** |
| Reject — English typed on a Cyrillic layout (`руддщ`, `цщкдв`), Cyrillic typed on a US layout (`ghbdsn`, `cgfcb,j`, `db,fxnt`), Ukrainian-only letters offered as Russian, outright nonsense | **38 / 38** |

Two things worth knowing from that run:

1. **No false accepts at all**, which is the direction that would visibly break text. Cross-layout
   renders are reliably rejected, so the "exactly one language accepts it" rule holds in practice.
2. **The single false reject is `Kyiv`** — absent from en_US (SCOWL). English proper nouns are thin in
   general, while the ru/uk dictionaries do carry `Москва`, `Київ`, `Україна`, `Львів`. A name the
   dictionary does not know is never auto-fixed; the manual trigger still converts it, and the
   always-convert list exists for words worth forcing. Not worth swapping a dictionary over.

Ukrainian and Russian morphology — the thing most likely to be weak in a free dictionary — came through
clean: every inflected noun, conjugated verb and declined adjective in the set was accepted, as were the
ё-omitted spellings most people actually type (`еще`, `ее`, `все`).

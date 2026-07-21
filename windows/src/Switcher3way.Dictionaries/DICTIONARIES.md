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

## Quality baseline (task 3.2, open)

Before shipping, compare these uk/ru dictionaries against the macOS `NSSpellChecker` baseline on a
representative word set — including punctuation-attached (`db,fxnt`→`вибачте`) and 2-letter cases —
and check that set in as a fixture so regressions are caught. Capture the baseline on a Mac.

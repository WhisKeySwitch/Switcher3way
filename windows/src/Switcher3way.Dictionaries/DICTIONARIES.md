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
| `bg` | [LibreOffice/dictionaries `bg_BG`](https://github.com/LibreOffice/dictionaries/tree/master/bg_BG) (bgOffice) | **MPL 1.1** (of GPL-2 / LGPL-2 / MPL-1.1) | see the note below — the shipped COPYING understates it |
| `sr` | [LibreOffice/dictionaries `sr`](https://github.com/LibreOffice/dictionaries/tree/master/sr) | **MPL 2.0** (of LGPL-3 / MPL-2 / GPL-3) | tri-licence stated in the package's own README |

### The Bulgarian licence needs reading twice
The `bg_BG` package ships a `COPYING` containing only the **GPL v2** text, and the packager metadata
in `wooorm/dictionaries` claims `(GPL-2.0 OR LGPL-2.1 OR MPL-1.1)` while the licence file it links to
contains no licence statement at all. Neither is sufficient on its own. The tri-licence is stated by
the upstream **bgOffice** project itself:

> «Лицензите, под които се разпространяват пакетите са GPLv2 или по-нова, LGPLv2 или по-нова и
> MPLv1.1.» — https://bgoffice.sourceforge.net/

That statement is quoted in `dict/bg.license` so the evidence travels with the file, and the original
GPL-2 `COPYING` is retained beside it as `bg-COPYING-gpl2.txt`. We rely on the **MPL 1.1** branch,
which puts Bulgarian on the same footing as Ukrainian.

### Serbian is Cyrillic only, deliberately
The upstream package also contains `sr-Latn`. It is not bundled: Serbian Latin and Serbian Cyrillic
are a 1:1 transliteration of the same language, so shipping both would make every Serbian word valid
in two "languages" at once and turn ordinary typing into a permanent ambiguity. Converting between
the two scripts is transliteration, not layout correction, and is a different feature.

### Languages considered and declined
| Lang | Why not |
|------|---------|
| `be` Belarusian | CC BY-SA 4.0 **or** LGPLv3 — no permissive branch, the same objection that ruled out `dict_uk`. Viable on precision: `be↔ru` collides at 4.6%, below the `ru↔uk` 14.2% already shipped. |
| `mk` Macedonian | Packaged only as GPL-3.0; absent from LibreOffice dictionaries. |
| `kk` Kazakh, `ky` Kyrgyz, `tg` Tajik | No freely licensed Hunspell dictionary found in either source. Kazakh has the strongest user case of all of them, and is declined only for that. |

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

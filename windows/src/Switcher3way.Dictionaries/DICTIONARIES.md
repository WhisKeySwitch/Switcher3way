# Dictionaries

`HunspellDictionaryValidator` loads `<lang>.dic` + `<lang>.aff` (Hunspell format) from a directory,
one file pair per 2-letter language (`en`, `ru`, `uk`). It uses the managed
[`WeCantSpell.Hunspell`](https://www.nuget.org/packages/WeCantSpell.Hunspell) — no native deps —
so validation is fully offline and independent of any OS language packs.

The integration and wiring are **done and tested** (see `HunspellValidatorTests`, which run against
tiny fixture dictionaries under `tests/Switcher3way.Core.Tests/fixtures/`). What is **not** yet in
the repo is the *real, full* en/uk/ru dictionaries — that's a deliberate, open decision:

## Bundling the real dictionaries — a licensing decision (open)

Detection depends entirely on dictionary quality, so the MVP must bundle real en/uk/ru Hunspell
dictionaries. **Their licenses vary and often are not MIT** — verify per source before committing:

| Lang | Common sources | Typical license (verify!) |
|------|----------------|---------------------------|
| en   | SCOWL / Hunspell `en_US`, LibreOffice | permissive-ish (SCOWL), varies |
| ru   | LibreOffice `ru_RU`, Firefox | BSD / GPL depending on build |
| uk   | `dict_uk` (brown-uk), LibreOffice `uk_UA` | GPL / LGPL / MPL tri-license (verify) |

A convenient aggregator is [`wooorm/dictionaries`](https://github.com/wooorm/dictionaries) (per-language
`index.dic`/`index.aff` with the license noted for each). LibreOffice dictionaries are another source.

**Implications for this MIT app:**
- Dictionaries are **data files**, bundled (aggregated), not linked as code — but each file stays
  under **its own** license. If you ship a GPL/LGPL dictionary, include that dictionary's license
  text next to it and honor its terms; keep MIT app code and dictionary data clearly separated.
- Prefer permissively-licensed dictionaries where quality is comparable; otherwise document each
  dictionary's license in this folder.

**When bundling:** drop the files in the app's dictionary directory named `en.dic/en.aff`,
`ru.dic/ru.aff`, `uk.dic/uk.aff` (or add a locale→2-letter mapping if you keep `en_US` etc. names),
point `HunspellDictionaryValidator` at that directory, and mark them `CopyToOutputDirectory` /
include them in the installer payload.

## Quality baseline (task 3.2, open)

Before shipping, validate the chosen uk/ru dictionaries against the macOS `NSSpellChecker` baseline
on a representative word set — including punctuation-attached words (`db,fxnt`→`вибачте`) and
2-letter cases — and check that set in as a fixture so regressions are caught. Capture the baseline
on a Mac (the shipping macOS app's validator) and compare.

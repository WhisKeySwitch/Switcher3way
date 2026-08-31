## Why

Three languages is not a principled number, it is where the fork started. Users have asked for more
Cyrillic languages, and the question is which ones can be added without spending the precision the
app was rebuilt around.

That question was answered by measurement rather than by intuition, and **the measurement contradicted
the intuition twice**.

### The collision matrix

Share of language A's own words that language B's dictionary also accepts — 20,000 sampled base
forms each, through the app's own validator:

```
    A/B       en      ru      uk      be      bg      sr
    en          —   0.0%   0.0%   0.0%   0.0%   0.2%
    ru       0.0%      —  14.2%   4.6%   7.9%   6.4%
    uk       0.0%   3.1%      —   1.6%   1.2%   1.6%
    be       0.0%   4.7%   4.2%      —   0.7%   0.9%
    bg       0.0%  14.9%   7.2%   2.6%      —  13.9%
    sr       0.0%   3.9%   4.0%   1.3%   5.1%      —
```

English collides with nothing. That is why today's app works as well as it does, and it means every
language added from here puts all of its new risk inside the Cyrillic cluster.

- **Belarusian was predicted to be the worst and is not.** `be↔ru` is 4.6–4.7% — *below* the
  `ru↔uk` 14.2% already shipped and tolerated.
- **Bulgarian was predicted to be the safest and has the highest overlap in the table** (`bg→ru`
  14.9%), from shared Slavonic roots and Russian affix expansion.

### Why overlap is not the same as risk

Overlap only becomes an *ambiguity* when the two layouts render the same keys identically. Belarusian,
Russian and Ukrainian all sit on ЙЦУКЕН, so for them overlap is the ambiguity rate directly. Bulgarian
uses **BDS** and Serbian is **QWERTZ-aligned**: the same keystrokes produce unrelated strings, so their
overlap mostly never gets the chance to fire. That reverses the ranking the matrix alone suggests.

### What it costs the users already here

The number that decides whether any of this may ship. The Ukrainian and English typo corpora from the
precision work, run with today's three languages and again with the candidates added:

```
uk typos, layouts en+uk+ru          0/4711 converted (0.00%)
uk typos, layouts en+uk+ru+bg+sr    0/4711 converted (0.00%)
en typos, layouts en+uk+ru          0/3117 converted (0.00%)
en typos, layouts en+uk+ru+bg+sr    0/3117 converted (0.00%)
```

**Nothing.** And measured in the worst case: the candidates were rendered through ЙЦУКЕН, which
neither uses, so their renderings coincide with Russian and Ukrainian instead of diverging. Real
layouts can only do better. The reason is that the typo guard and the short-word phrase rules decide
before candidate languages are consulted — the precision work is what makes expansion affordable.

## What Changes

- **Bundle Bulgarian and Serbian** (LibreOffice `bg_BG` and `sr`, both tri-licensed with **MPL-1.1**
  selectable — the same footing as the Ukrainian dictionary already shipped). Cost: **0.30 MB and
  1.14 MB compressed**, on a 46.7 MB package.
- **Vowel sets for both** in the `Vowels` table the shape heuristic reads.
- **Serbian needs the syllabic R**, and this is the one real defect found. `WordShape` requires a
  vowel, and `крв`, `прст`, `врх`, `трг`, `црн`, `брз`, `крст`, `врт`, `смрт` — blood, finger, top,
  square, black, fast, cross, garden, death — are ordinary Serbian words with no vowel in them. Left
  unhandled, correctly typed Serbian would read as gibberish and could be *rescued into another
  language*, which is a false conversion in the app's least forgivable direction.

  Worth recording how this was nearly missed: the aggregate count of vowel-less Serbian words is
  0.14%, which reads as negligible. The words behind that number are among the most frequent in the
  language. Counting types rather than tokens hid it, and only checking specific words surfaced it.

## What this does not do

- **No new ambiguity machinery.** `NWayResolver` resolves exactly one ambiguous pair (`{ru, uk}`) and
  keeps anything wider. Because Bulgarian and Serbian do not share ЙЦУКЕН, they do not join that
  cluster, and "keep" is the right precision-first answer for the pairs they do form. A third ЙЦУКЕН
  language *would* require generalising both that rule and the single `AmbiguousLang` preference —
  which is one of the reasons Belarusian is not in this change.

## Languages considered and declined

- **Belarusian** — viable on precision, and cheaper than feared. **Blocked on licensing:** the
  LibreOffice `be_BY` dictionary is CC BY-SA 4.0 **or** LGPLv3, with no permissive branch, in an MIT
  app. This is the same judgement that rejected `dict_uk` for Ukrainian. It is also the largest at
  2.00 MB compressed, and the only candidate that would force the ambiguity model to be rewritten.
- **Macedonian** — packaged only as GPL-3.0; absent from LibreOffice dictionaries.
- **Kazakh, Kyrgyz, Tajik** — no freely licensed Hunspell dictionary found in either source. Kazakh is
  the one with the strongest user case (a large kk/ru bilingual population switching layouts daily),
  and it is declined for want of a dictionary rather than for want of merit.

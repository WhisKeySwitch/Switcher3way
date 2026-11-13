# Proposal

## Why

A field log (1.7.2, 28 Oct – 13 Nov 2026) shows Ukrainian typed on the English layout ending up as
`Це все, xbv z допомогти`: the words on both sides of `чим я` were converted and the two in the middle
were not. To the user it looks as though the app turned two Ukrainian words into English. It did not.
It never converted them, and then a phrase correction rewrote everything around them. 4 of the log's 15
phrase corrections left a word behind like this (`z`/я, `d`/в, `dsy`/він, `ukj,fk`/глобал,
`xbv z`/чим я). All of them were Ukrainian.

There are two causes, and each is enough to produce the effect:

- **Common Ukrainian words are missing from the short-word list.** Since 1.6.0 a dictionary hit
  under four letters counts only if the word is on its language's list in `ShortWords.swift`. The macOS
  dictionary accepts `він`, `чим`, `от`, `ото`, `же`, `їду`, `йти`, `тю`, `ок`, but the list lacks
  them, so the app treats them as "not a word in any installed language". In this log alone it refused
  `він` 9 times, `от` 8, `ото` 4, `ок` 4 and `же` 3. The coverage test reads 100% because its sample
  prose never uses these words.
- **A phrase correction retypes unconverted words exactly as they were typed.** A word left alone because
  it is not a word anywhere, or because it is a single letter, is retyped verbatim even when the
  correction converts the words on both sides of it. For such a word that is the wrong outcome.

## What Changes

- Check the short-word lists of Ukrainian, Russian and Bulgarian against every 1–3 letter string the
  macOS dictionary accepts in that language. Each one gets an explicit decision, either a word people
  type or dictionary noise, and the decisions are recorded so the next review starts from them. Add the
  missing words, and add them to the coverage fixture so a gap like `він` fails the suite.
- When a phrase correction already spans a word that was left alone because it is not a word in the
  language it was typed in (including single letters), convert that word along with its neighbours. Such
  a word still never *starts* a correction. A lone English typo stays as typed, as today.
- Regenerate `windows/src/Switcher3way.Core/ShortWords.cs`, and give the Windows `PhraseTracker` the
  same rule.

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `automatic-conversion-on-word-boundaries`: the phrase-correction requirement no longer reproduces
  every non-defaulted word verbatim. A word that is not a word where it was typed and lies inside the
  corrected segment is converted with it.
- `layout-switching-and-language-detection`: the short-word rule gets a requirement of its own. A
  language's real short words SHALL be recognised, and the list SHALL be reviewed against everything
  the dictionary accepts at that length.

## Impact

- `Sources/Switcher3wCore/ShortWords.swift` (lists), `PhraseTracker.swift` (a new word kind, and how
  the correction renders it), `Sources/Switcher3w/AppDelegate.swift` (records a non-word keep with the
  new kind).
- Tests: `ShortWordFixture`/`ShortWordsTests`, `PhraseTrackerTests`, and a regression case for each
  of the four log episodes.
- Windows: `ShortWords.cs` (generated), `PhraseTracker.cs`, and their tests; ships on the next
  `windows-v*` tag.
- Ships as macOS 1.7.3 from `main`. No settings change.

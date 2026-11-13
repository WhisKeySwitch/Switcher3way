# Design

## Context

See proposal.md for the field episodes. Two mechanisms produce them:

- `NWayResolver.evaluate` counts a dictionary hit under four letters only when `ShortWords.admits` agrees.
  The lists in `ShortWords.swift` are written by hand. The coverage test (`ShortWordPrecisionTests`)
  checks them against the short words of a fixed sample prose (`ShortWordFixture.inProse`). A word that
  prose never uses can be missing without any test noticing. That is how `він` and `чим` went missing.
- `PhraseTracker` records every word that was left alone as `.neutral`, and `correction(toLang:)`
  reproduces neutral words verbatim. `AppDelegate` already knows *why* a word was kept
  (`KeepReason`), but that reason is discarded at the point it records the word. A keep for
  `.notAWordAnywhere` and a keep for `.validInCurrent` with a short word land in the tracker
  indistinguishable. A single letter fails the soft gates and keeps as `.notAWordAnywhere` too.

Measured on macOS 27 (2026-11-13), every 1–3 letter string over each language's alphabet, checked
with `NSSpellChecker`:

| language | 1 letter | 2 letters | 3 letters | total |
|---|---|---|---|---|
| uk | 33 | 119 | 1190 | 1342 |
| ru | 33 | 219 | 1764 | 2016 |
| bg | 30 | 170 | 1118 | 1318 |

The dictionary accepts every single letter. It takes 17 s for all three languages.

## Goals / Non-Goals

**Goals:**
- No word under four letters that people commonly type is missing from the uk, ru or bg lists, and the
  suite fails when one is.
- A phrase correction never leaves an unrecognised word stranded between converted words.

**Non-Goals:**
- Reviewing English the same way. English short-word noise was the original 1.6.0 defect and the
  English list was built around it. Its 26-letter alphabet makes the review just as cheap, but no field
  log shows an English gap. Left for a later change, if one does.
- The Western languages on the `western-languages` branch. When that branch is rebased onto this
  change, the same review applies to fr/it.
- Changing the four-letter threshold or the held-run rules.

## Decisions

### 1. Review against the dictionary, not against more prose

The gap came from measuring coverage against a sample text, and any sample text has the same blind
spot. Instead, the review enumerates what the dictionary accepts. That set is finite and small (table
above), and it is exactly the set where the list's verdict matters. A string the dictionary rejects is
never a hit, so the list cannot affect it.

Each accepted string is classified once, by a person or by Claude with a person checking the result,
as one of:
- **typed word**: goes into `ShortWords.swift`. Includes colloquial and profane words people actually
  type, because a missing entry converts real text away.
- **noise**: goes into a recorded noise set in the test target (`ShortWordReview.swift`), so the
  decision is kept and a reviewer sees it was made.

The test enumerates the live dictionary, and it fails on any accepted string that is in neither set,
naming it. A macOS update that adds strings to a dictionary then shows up as a test failure listing
exactly what to review. That is the intended behaviour, and the same cost the dictionary canaries
already carry.

*Alternative considered:* add the ten words from this log and widen the sample prose. It is cheaper,
and it fixes the next report only if the prose happens to contain the next missing word.

*Alternative considered:* believe the dictionary for 3-letter words and keep the list only for 1–2
letters. Rejected: 1,190 accepted 3-letter Ukrainian strings include abbreviation noise of exactly the
`wt` kind, which was the 1.6.0 defect.

### 2. A word kind for "not a word where it was typed"

`PhraseTracker.WordKind` gains `.unrecognised(lang:)`. It means the word was left alone, and is
not a word in `lang`, the language of the layout it was typed on. `AppDelegate` records a
`.keep(.notAWordAnywhere)` with this kind. Every other keep reason stays `.neutral`.

`correction(toLang:layoutID:)` changes in one place. Inside the segment it builds (from the first
defaulted-to-another-language word to the end), an `.unrecognised` word whose `lang` differs from the
target is re-rendered through the target layout, exactly as a defaulted word is. The segment's start
is still found from defaulted words only. So an unrecognised word never starts a correction, and an
English typo typed alone is untouched (spec scenario "does not start a correction").

Ending up in a correction span means a held word before it and a converting word after it both read
as the target language. A string that is a word in no installed language, sitting between them, is
far likelier to be that language on the wrong layout than a typo of the typed language. All four
field episodes were.

*Alternative considered:* record `.notAWordAnywhere` keeps as `.defaulted(currentLang)`. Rejected:
defaulted words *start* corrections, so a lone English typo followed by a Ukrainian word would be
converted into Cyrillic gibberish.

*Alternative considered:* fix only the short-word lists. Rejected: `глобал` (jargon, 6 letters) was
stranded the same way, and no list can cover jargon and names.

### 3. Windows carries the same rule

`windows/src/Switcher3way.Core/ShortWords.cs` is generated from the Swift file. The generator is
`windows/tools/gen-shortwords.py` on the `western-languages` branch, which is not on `main`. This
change brings that script over on its own. The Windows `PhraseTracker` gets the same word kind, with
its own test of the `чим я` episode.

## Risks / Trade-offs

- [Adding real short words makes some wrong-layout renderings count as words, so they are no longer
  converted] → `ShortWordPrecisionTests` and the en+uk+ru combination measurement are run before and
  after, and the typo bar of 0.28% must hold. Any addition that moves a number is quoted in tasks.md.
- [The review is a judgement call over ~4,600 strings] → it is recorded per string, so it can be
  checked and corrected one entry at a time. Ambiguous cases (archaic, regional) lean to *typed word*,
  because an omission is the dangerous direction.
- [Re-rendering an unrecognised word could convert a real English typo that happens to sit inside a
  Ukrainian correction span] → only possible when the words on both sides of it convert to the other
  language, and the whole correction stays one ⌥-undo.
- [A macOS dictionary update fails the suite] → intended: the failure lists the strings to classify.

## Migration Plan

- No settings or stored state change. The phrase memory is in-memory only.
- Ships as macOS 1.7.3 from `main`: bump `version.json` from 1.7.2. Windows rides the next
  `windows-v*` tag after `dotnet test`.
- Rollback is a revert.

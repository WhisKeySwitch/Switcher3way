## Context

See proposal.md — Why. The decision core is `Sources/Switcher3wCore/NWayResolver.swift` (mirrored
line-for-line by `windows/src/Switcher3way.Core/NWayResolver.cs`); the app-side bookkeeping that
turns outcomes into phrase records lives in `AppDelegate.handleAutoConvert` (Windows: `Engine.cs`).
Three constants shape the length bands today: `undecidableBelow = 4`, `nearMissTrustedFrom = 6`,
`rescueFloor = 4`. The field log that motivates this change is the evidence base; every rule below
is tied to a count in it.

Constraints that shape the approach:

- **Precision is measured, not asserted.** `2026-08-23-stop-converting-typos` bought 0% typo
  conversion; anything here that relaxes a guard must be shown not to move that number. The Windows
  `TypingSimulationTests` is the only paragraph-level measurement and must be re-run.
- **Every decision is logged, including keeps.** New outcomes need a reason string on both ports.
- **The two cores stay legible side by side.** Same constants, same method shapes, same test inputs.
- **The rewrite is the dangerous code.** Any path that can avoid erase-and-retype should.

## Goals / Non-Goals

**Goals:**
- Restore the documented length band of the typo guard and stop it vetoing same-text uk↔ru words.
- Make the phrase lock require real evidence (letters, and at least four of them).
- Resolve uk/ru ambiguity by preference when the lock is irrelevant to it.
- Admit contractions and hyphenated words through the soft gates.
- Settle a lone vowel-less held word, gated on a zero-false-conversion fixture measurement.
- Same edits, same tests on Windows.

**Non-Goals:**
- Changing the all-caps veto, the `undecidableBelow`/`nearMissTrustedFrom`/`rescueFloor` values, or
  the held-run size of two.
- Improving the English dictionary's acceptance of two-letter abbreviations (`wt`, `ye`, `uk`).
  Noted as a residual; the right fix is a stop-list in the validator, a separate change.
- Any change to the manual trigger, `TextConverter`, or the rewrite verification.

## Decisions

### D1. Gate the typo guard on `coreLength >= nearMissTrustedFrom`, not on falling out of the short-word block
Today the `coreLength < nearMissTrustedFrom` block returns for phrase-agree, phrase-disagree and held,
and *falls through* for 4–5 letters with no phrase — straight into the `TypoGuard.nearMiss` call.
The fix is one condition on that call: `weighEvidence && coreLength >= Self.nearMissTrustedFrom`.
Alternative considered: lowering `nearMissTrustedFrom` to 4 to match the code. Rejected — the
constant is the measured value (30–40% false alarms at four); the code is what drifted.

### D2. Same-text winner: a layout-only decision, taken only with the phrase's corroboration
When `letterCore(winner.converted).lowercased() == letterCore(current.string).lowercased()` AND
`phraseLang` is the winner's language, the guard is skipped and the outcome is a `.convert` whose
`original == converted`. Without that corroboration the word is kept with a new
`KeepReason.sameTextUncorroborated`, at every length — decided before the length band, because most
of the corpus typos that are real Russian words are four and five letters (даже, слов, добр) where no
guard discriminates. **Measured:** the unconditional version converted 15 of 1,399 Ukrainian corpus
typos into Russian layout flips (програма→программа, адже→даже), exactly the failure
`2026-08-23-stop-converting-typos` was written to stop; the corroborated version converts 0 of them.
The cost is recall on the first same-text words of a Russian-on-Ukrainian-layout session, until a
ы/э word converts and locks the phrase to ru. Rather than a new
outcome case, `Decision` gains a computed `isLayoutOnly` (original and converted equal). The app
checks it before planning a retype: switch the layout, record the word as `.locked(lang)`, run the
phrase-correction check (a locked word may still re-render earlier defaulted words — that path *does*
retype, as today), show the caret chip in a "layout switched" form, log `auto: layout only → ru`.
Alternative: a distinct `Outcome.switchLayout`. Rejected — it would fork every `switch` on both ports
for a property that is a one-line predicate on the existing decision.

Why skip the guard here at all: the guard chooses between "you mistyped" and "wrong keyboard", and
both stories leave *this* text on screen. The only thing at stake is the next word's letters, and a
wrong switch there costs exactly what a missed one does. Meanwhile uk holds a cognate one edit from
nearly every ru word, so on this path the guard's precision in the log is 0 of 10.

### D2b. The short-word band is judged on the shorter of the two letter cores
`coreLength = min(typed core, min over winners of winner core)`. Punctuation keys are letters on the
other layout (`[`↔х, `;`↔ж, `.`↔ю), so a four-letter typed core can have a two-letter winner: "рухх"
renders "he[[" whose core is "he", and judging by the typed side converted a typo into "he[[" — the
one short-typo conversion the Windows `ShortTypos` test caught after D1 (1/403). With the shorter
core deciding, that word is held for the phrase and the count is back to 0/403.

### D3. Empty letter core is never valid — enforced in the candidate loop, on both ports
`valid = !core.isEmpty && dict.isValidWord(core, lang)`. `NSSpellChecker` and Hunspell both accept
the empty string. This also stops "10" or "." from being `.validInCurrent` and therefore from locking
the phrase (the most common poison in the log: 3,453 of 3,865 validInCurrent lines had an empty core,
of which the phrase-disagrees analysis traced 6 directly to a refusal, and the rest hid short-word
decisions behind an English lock in ways the log cannot count).

### D4. Lock the phrase on a current-language word only from `undecidableBelow` letters
The resolver keeps returning `.keep(.validInCurrent)` for short words (nothing else changes about
the word), but the *caller* locks only when `letterCore.count >= NWayResolver.undecidableBelow`.
The length is a fact the resolver already computes, so expose it: `KeepReason` stays an enum, and
`Outcome.keep` grows no payload; instead the app recomputes the core length (one call). Alternative:
a new `KeepReason.validInCurrentButShort`. Rejected — the log reason string "already a word in this
layout's language" is right in both cases, and a second reason would split it for no diagnostic gain.
Windows `Engine.cs:275` gets the same length condition.

Why four: it is the floor below which the other direction already refuses to decide, for the same
reason — a quarter of two-letter Latin strings are "words". `e`, `z`, `wt`, `ye`, `10`, `.` locked 35
of the 48 phrase-disagrees keeps in the log. Cost: a short *real* word (`так`, `що`, `не`) no longer
locks; the held run and the preference already cover what the lock did for them.

### D5. Ambiguity: lock ∉ winners → preference
In the `.ambiguous` branch: `let lockIsCandidate = lockedLang.map { l in winners.contains { $0.lang == l } } ?? false`;
`pref = lockIsCandidate ? lockedLang! : ambiguousLang`. Log says which was used. Word is recorded
`.defaulted`, as today; the correction machinery's "contradictory lock" rule still prevents a later
retro-correction across the en lock, which is the right conservatism.

### D6. Soft gates: internal `'`, `’`, `-` are letters for the gate's purpose
`passes` currently requires `allSatisfy(isLetter)`. Change to: every character is a letter, or is one
of `'`/`’`/`-` and is neither first nor last (letterCore already trims edges, so an internal one is the
only way it appears). The all-caps, camelCase and mixed-script checks run on letters only, as now.
`TypoGuard.nearMiss` then sees a core with an apostrophe; its insert/substitute loops use the
alphabet and stay correct. Windows `PassesSoftGates` mirrors it.

### D7. Vowel-less held word: a `WordShape.hasNoVowel` signal, admitted by measurement
`handleHeldWord` already receives `winners`; when `winners.count == 1` and
`WordShape.hasVowel(letterCore(original).lowercased(), vowels: dict.vowels(currentLang)) == false`,
it settles the run at once (reusing `settleHeldRun`, so the held words before it convert together).
Vowel sets come through `DictionaryValidating.vowels(_:)` as the rescue already does; an empty set
switches the rule off (fail-open, same convention). The rule ships behind a fixture test
(`VowelLessFixture.swift` / `.cs`): legitimate vowel-less tokens per language — uk/ru `хз`, `пн`,
`вт`, `ср`, `чт`, `пт`, `сб`, `нд`, `тд`, `тп`, `др`, `мб`, `млн`, `грн`, `смс`, `тчк`; en `msg`,
`pwd`, `ctrl`, `npm`, `cmd`, `src`, `dst`, `tbd`, `btw`, `thx`, `pls`, `rn`, `ty`. Each is typed as
itself; the test evaluates it, and the rule must convert none. If the fixture cannot reach zero with
the real dictionaries, the task list says to leave the rule disabled (vowel check short-circuited to
"has a vowel") and record the offending tokens in tasks.md rather than lower the bar.

Alternative considered: settle a single held word on Enter. Rejected — Enter sends the message in
chat; the rewrite cannot complete before it, and racing it is exactly the class of bug the rewrite
guards exist to prevent.

### D8. Order of implementation and measurement
Core rules first (D1, D3, D6 pure resolver/gates), then app-side lock and ambiguity (D4, D5), then
the same-text path (D2, touches the apply path), then D7 last with its fixture. After D1–D6 on
Windows, re-run `TypingSimulationTests`; the typo-conversion rate is the gate for the whole change.

### D9. Short words need corroboration from a curated list, on both sides
`NWayResolver.undecidableBelow` guarded only the *convert* use of a short dictionary hit. The *keep*
use had no guard at all: `current.isValid` returns before length is ever considered, so one piece of
dictionary noise in the language being typed silently disables the fix. That is the reported defect —
`це` typed on the English layout lands as `wt`, `NSSpellChecker` calls `wt` an English word, and the
resolver reports "already a word in this layout's language". Measured in the field log: 8 for `wt`, 5
for `ye`, plus `Hey`/Рун, `key`/лун, `elm`/Будь; and 11 cascades where the same noise locked the
phrase to English and later short words were then refused for disagreeing with it.

`ShortWords.admits(core, lang)` is ANDed into candidate validity in the one place validity is
computed, so it applies to the typed side and the candidate side alike. An **allow**-list, not a
list of junk: the junk is unbounded (any of 676 two-letter strings, 160 of which the dictionary
accepts) while the real short words of a language are a small closed set. Generated once into
`windows/src/Switcher3way.Core/ShortWords.cs` from the Swift file, so the two ports cannot drift.

The list is needed on **both** sides because the defect is symmetric: `the` typed on the Ukrainian
layout lands as `еру`, which the Ukrainian dictionary accepts. Measured over the corpus, of 46
distinct short Ukrainian words 33 have a "valid" reading in another language, and of 50 English ones
9 do — that is the population this decides.

**The two errors are not symmetric, and that sets the tuning direction.** A word missing from the
list of the language being typed in stops being valid there, so a correctly typed word could be
converted away; a word missing from another language's list costs one trigger tap. So the lists are
generous and gated by coverage over real prose (`ShortWordPrecisionTests`; the first run caught `так`,
`там`, `нет` and `он` missing from Russian). The short-word band limits the blast radius — under four
letters the resolver holds rather than converts unless the phrase agrees — but does not remove it.

Side effect worth naming: the Russian dictionary also accepts `це`, which used to make the word
ambiguous and hand it to the preference setting. `це` is not Russian, so the list drops that reading
and the word is now unambiguously Ukrainian. The same mechanism removed the `uk`/`гл` ambiguity.

## Risks / Trade-offs

- [D1 lets 4–5 letter typos through where no phrase is settled] → The archived measurement says
  0% typo conversion was measured with the guard *documented* at six; re-running
  `TypingSimulationTests` after the change verifies the number rather than assuming it. If it moves
  off zero, the band constant is what gets discussed, not the gate.
- [D2 switches to Russian on a Ukrainian typo that happens to be a Russian word] → Measured at 15 of
  1,399 corpus typos for the unconditional rule, which is why it now requires the phrase to read as
  the winner's language first (0 of 1,399). The price is that the first same-text words of a
  Russian-on-Ukrainian-layout session stay unconverted until a ы/э word locks the phrase.
- [D4 removes lock evidence that helped `short word, phrase agrees` conversions] → One such line in
  the whole log; the held run covers the same case for runs of two, and D7 covers lone words.
- [D6 admits `l'` / `d'` style tokens] → They still need a dictionary hit in exactly one other
  language and the length band; the gate was never the thing protecting against them.
- [D7 is new evidence with no field history] → Fixture gate at zero false conversions; the rule is
  disabled by construction if the fixture fails; the log reason names it so a field log can indict it.
- [Two ports drift] → Same test inputs listed in the Windows spec delta; task list pairs each Swift
  test with its C# twin. The short-word lists are generated from the Swift source into the C# file
  rather than typed twice.
- [D9's lists are incomplete for a dialect, a name, or vocabulary the corpus does not contain] →
  Coverage gate over real prose, generous lists, and the short-word band means an omission holds the
  word rather than converting it unless a phrase already disagrees. The failure mode is a missed fix,
  not mangled text, except inside a phrase already settled the other way.
- [D9 changes what `validInCurrent` means, so the log reason for some short words becomes "not a word
  in any installed language"] → Accurate rather than misleading: the dictionary's verdict on that
  word is no longer being believed. Both ports log it the same way.

## Migration Plan

No data or settings migration. macOS ships as 1.6.0 (behaviour change, not a patch) through the
existing updater; Windows rides the next `windows-v*` tag together with the unreleased Bulgarian and
Serbian dictionaries. Rollback is the previous release on either channel; nothing persisted changes
shape.

## Open Questions

- Which exact tokens belong in the vowel-less fixture is a judgement call that can grow after the
  first measurement without changing the rule or the specs; start with the list in D7.

## Measured outcome (2026-09-08, Windows core suite, real Hunspell dictionaries; baseline = `main`)

| Measure | Baseline | After |
|---|---|---|
| Recall, uk typed in en (word in isolation) | 45/87 (51.7%) | 50/87 (57.5%) |
| Recall, en typed in uk (word in isolation) | 43/83 (51.8%) | 58/83 (69.9%) |
| Precision, uk typos wrongly converted | 0/1399 | 1/1399 (0.07%: друкую→рукую→`here.`) |
| Precision, en typos wrongly converted | 0/1049 | 1/1049 (0.10%: fine→ifne→`шату`) |
| Short (≤5) typos wrongly converted | 0/403 | 0/403 |
| Paragraph simulation, own language, words mangled / layout switches | 0 / 0 | 0 / 0 |
| Vowel-less abbreviations the held-word rule would convert | — | 2/76 macOS, 0/76 Windows → rule still OFF |
| Short-word list coverage over prose (en / uk / ru) | — | 100% / 100% / 100% |
| Field-log words now recoverable (`wt`→це, `ye`→ну) | kept as English | converted, real dictionary |

The short-word allow-list (D9) also removed six of the eight vowel-less false conversions on macOS
and all eight on Windows, because most of them were junk winners rather than junk in the typed
language. macOS still measures 2, both `см` reading as `cv`, which is on the English list because
people do type CV. The bar is zero on both ports, and tuning the list to reach it would be tuning the
evidence, so the vowel-less rule stays off.

The two remaining typo conversions are the documented cost of consulting the one-edit guard only from
six letters: both are five-letter typos (or a four-letter one with a four-letter winner) that render
as a real word of the other language. Paragraph-level damage stays at zero because the phrase catches
them in context.

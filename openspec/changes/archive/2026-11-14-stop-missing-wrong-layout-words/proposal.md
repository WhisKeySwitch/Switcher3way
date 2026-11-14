## Why

A twelve-day field log (2026-08-27 to 2026-09-08, macOS 1.5.1 → 1.5.2; 5,731 auto decisions, 121
manual triggers) shows the app leaving wrong-layout words alone far more often than its design says it
should. Every one of the 26 words the typo guard refused was a real wrong-layout word (Дякую, Слава,
давай, слишком, наверное, chat, fine…), not one typo among them; 35 of the 48 "phrase disagrees" keeps
were locked by a token that carries no evidence ("10", ".", "e", "wt"); and a handful of valid winners
were vetoed for containing an apostrophe or hyphen. Each miss costs the user a trigger tap, and the
user has said so: "still too many times auto-conversion not firing". The 1.4.0 typo-guard release
bought its 0% typo conversion partly with recall it never meant to spend — the code applies the guard
two letters below the threshold its own documentation and the archived measurement set.

## What Changes

- **Consult the one-edit typo guard only from six letters up**, where it was measured to discriminate.
  Four- and five-letter words with no phrase to contradict them convert on the dictionary hit, as the
  resolver's comments and `2026-08-23-stop-converting-typos` already say they should. (16 of the 26
  refused words in the log.)
- **Switch the layout, without retyping, on a word spelled the same in the sibling language once the
  phrase reads as that language** — the Ukrainian↔Russian same-script case, where Ukrainian almost
  always holds a cognate one letter from any Russian word, so the typo guard fired on everything and
  the layout never switched (10 of 26). Measured during implementation: doing this *without* the
  phrase's corroboration flipped 15 of 1,399 Ukrainian corpus typos into Russian (адже→даже), the
  failure the typo guard exists to stop, so the switch requires the phrase and otherwise keeps with its
  own logged reason.
- **Stop weak tokens from locking the phrase.** A token with no letters at all ("10", ".", "))") SHALL
  not count as a valid word anywhere (today an empty letter core passes every dictionary). A word valid
  in the current language SHALL lock the phrase only from four letters, the same floor below which the
  other direction refuses to decide; shorter ones are recorded as neutral. (35 of 48 phrase-disagrees
  keeps; e.g. "10" locked English and хвилин was then refused.)
- **Fall back to the ambiguity preference when the phrase lock names a language that is not a
  candidate** (phrase locked to English by "wt", then печально valid in uk and ru was kept as "nothing
  to choose between them").
- **Let an internal apostrophe or hyphen through the soft gates.** `You're`, `That's`, `Кто-то` were
  valid winners vetoed by the letters-only rule, while the same words pass when typed in their own
  layout. Leading/trailing punctuation is still trimmed; all-caps, camelCase and mixed-script vetoes
  are unchanged. (6 in the log.)
- **Settle a lone held short word when its typed rendering has no vowel at all** and it reads as
  exactly one language ("щт" → on, "тщ" → no, "Рш" → Hi, "nfr" → так). Gated on measurement: the
  extension ships only if a fixture of legitimate vowel-less abbreviations (хз, пн, смс, грн, msg, pwd,
  ctrl…) produces zero false conversions. 46 words were held in the log and only 5 runs ever settled;
  the rest were one-word chat messages sent before a second word could arrive.
- **Stop dictionary noise from keeping a short word.** Under four letters a dictionary hit must now
  be corroborated by a curated list of words the language's speakers actually type. This is the
  defect reported as "it keeps converting це into wt": the app converted nothing — the user typed
  Ukrainian with the English layout active, `це` landed as `wt`, and `NSSpellChecker` calls `wt` an
  English word, so the resolver reported "already a word in this layout's language" and left it.
  8 occurrences for `wt`, 5 for `ye`, plus `Hey`/Рун, `key`/лун, `elm`/Будь, and 11 cascades where
  that same noise locked the phrase to English and refused the short words after it. The list is
  symmetric, because `the` typed on the Ukrainian layout lands as `еру`, which the Ukrainian
  dictionary accepts.
- **Windows core gets the same edits** — it shares the algorithm and has the identical fall-through,
  the identical empty-core validity, and the identical lock rule. Rides the next `windows-v*` tag.
- Not changed, on purpose: the all-caps veto (WTF/SSO/ADO typed in Cyrillic; 3 triggers, and a
  correctly typed Cyrillic acronym rendering as a Latin word is the same risk in reverse).

## Capabilities

### New Capabilities

_None._

### Modified Capabilities

- `layout-switching-and-language-detection`: the length band where the one-edit typo guard applies,
  the same-text exemption from it, the same-text layout-only conversion, what counts as a valid word
  (never an empty letter core), which kept words settle the phrase, and the vowel-less settlement of a
  lone held word.
- `automatic-conversion-on-word-boundaries`: soft gates admit an internal apostrophe or hyphen; an
  ambiguous word whose phrase lock is not among its candidates resolves by the preference.
- `windows-platform-support`: the precision-first semantics requirement gains the same rules so the
  ports stay legible side by side.
- `detection-core-testability`: the suite covers each new rule, and a fixture-driven measurement gates
  the vowel-less held-word extension.

## Impact

- **macOS core:** `Sources/Switcher3wCore/NWayResolver.swift` (typo-guard gate, same-text path,
  empty-core validity, lock signal, short-word corroboration), `SoftGates.swift`
  (apostrophe/hyphen), `WordShape.swift` (vowel-less test), new `ShortWords.swift` (the curated
  lists); `Tests/Switcher3wCoreTests/` (new cases, three new fixtures).
- **macOS app:** `AppDelegate.swift` — lock only on a qualifying keep, preference fallback for
  ambiguity, layout-only apply for same-text decisions, held-word settlement on the vowel-less signal.
  `TextConverter.swift` is unchanged; the same-text path bypasses it.
- **Windows:** `windows/src/Switcher3way.Core/NWayResolver.cs`, `SoftGates.cs`, `WordShape.cs`,
  `windows/src/Switcher3way.App/Engine.cs`, and `windows/tests/Switcher3way.Core.Tests` including
  `TypingSimulationTests` re-run to confirm typo conversion stays at 0%.
- **Docs:** `CLAUDE.md` current-state bullet, `docs/user-guide*.md` only if the visible behaviour
  needs a sentence (the same-text layout switch produces a chip with identical text on both sides —
  the chip should say "layout switched" instead).
- **Risk profile:** items 1, 3, 4, 5 restore documented behaviour or fix outright bugs; item 2 relaxes
  a precision guard for the same-script case where a wrong decision moves only the layout, never the
  text; item 6 is new evidence and is measured before it is enabled.

# Phrase-Aware Ambiguity Resolution

## Why

Today an uk/ru-ambiguous word («добре», «там») typed in the wrong layout is left as Latin gibberish — the precision-first rule keeps it because the dictionaries can't pick a side. In practice this leaves the most common words unconverted («Lj,ht? що є прогрес») while the rest of the phrase converts fine. The user wants ambiguous words converted to a preferred language (Ukrainian by default) and, when the phrase later proves to be the *other* language (a ru-only word appears), the earlier defaulted words re-converted automatically.

## What Changes

- **Ambiguity default**: a word that is NOT valid in the current (typed) language but valid in more than one other language is converted to the *preferred ambiguity language* (new setting, default Ukrainian) instead of being kept. Setting value "off" preserves today's keep behavior.
- **Phrase tracking**: words typed since the last hard reset (Enter/Tab/arrows/click/app switch — the same events that reset the word buffer) form a *phrase*. Each evaluated word is recorded with its keystrokes, on-screen text, and classification (defaulted / locked-to-language / neutral).
- **Phrase-level correction**: when a word valid in exactly ONE language arrives and the phrase already contains words that were *defaulted* to a different language — and no word locked to a conflicting language — the defaulted words are re-converted to the new language in a single retype of the segment (from the first defaulted word through the current word), and the layout switches there. Contradictory phrases (uk-only word seen, then ru-only) are left untouched — precision-first.
- **Phrase lock beats the setting**: once a phrase contains a word valid in exactly one language, later ambiguous words in that phrase default to the locked language (unless the setting is "off", which keeps them unconverted as today).
- New Auto-fix setting UI (popup: Ukrainian / Russian / Do not convert) + user-guide updates (EN/UK/RU).

## Capabilities

### New Capabilities

_None._

### Modified Capabilities

- `automatic-conversion-on-word-boundaries`: ambiguous words are converted to the preferred/locked language instead of kept; new phrase-correction requirement (re-convert defaulted words when the phrase's language is disambiguated later).
- `settings-and-exception-management`: new "language for ambiguous words" setting (Ukrainian default / Russian / off) surfaced on the Auto-fix tab.

## Impact

- `Sources/Switcher3w/NWayDetector.swift` — `resolve` exposes the ambiguous candidate set instead of collapsing it to nil.
- New `Sources/Switcher3w/PhraseTracker.swift` — phrase word history, lock state, correction plan builder.
- `Sources/Switcher3w/AppDelegate.swift` — `handleAutoConvert` consults the tracker; correction retypes go through the existing abortable `beginCycle` (single-step, undoable by ⌥).
- `Sources/Switcher3w/KeyboardMonitor.swift` — phrase reset signals on the existing full-reset events.
- `Sources/Switcher3w/SettingsManager.swift` (`com.switcher3w.ambiguousLang`), `SettingsWindowController.swift` (Auto-fix popup), `Localization.swift` (new strings en/uk/ru; others fall back to English).
- `docs/user-guide.md` + `.uk.md` + `.ru.md` — auto-fix section (compiled into in-app help on build).
- Builds on the fix-retype-typing-race abort guard: segment retypes are longer, so the "abort on concurrent typing + restore" machinery is a prerequisite.

# Proposal

## Why

The macOS app is built around one combination: English, Ukrainian and Russian. People who write other
languages already use it with whatever two or three layouts they have enabled in macOS — English with
Bulgarian, English with German and French — and today those languages either fail open or are not
understood at all. Supporting more languages does not mean running all of them at once. It means that
**any small combination a person actually enables** is detected with the same precision the original
three get, and a combination that cannot reach that precision is not offered.

Measured 2026-09-24..28 on this Mac with the real `NSSpellChecker` and the real macOS layout tables:

- **The macOS spell checker covers Bulgarian, German and French**, and they are as strict as the
  Ukrainian dictionary on random strings (Bulgarian rejects 399/400). It has no Serbian, Belarusian or
  Kazakh dictionary; for those it accepts everything, so they cannot be supported on macOS.
- **Short-string junk is as common in Bulgarian as in the languages that needed a short-word list.**
  Bulgarian accepts 170 of 900 two-letter strings (Ukrainian 119/1024, Russian 214/1024). Without a
  list, every language added today would reintroduce the "це kept as wt" defect.
- **Transliterating layouts cost their own user.** Bulgarian Phonetic renders `reda` as `реда`, so
  English typos become valid Bulgarian: English typo conversions rose from 0.26% to 0.71%. The same
  holds for layouts that already ship — Russian Phonetic 1.22%, Ukrainian QWERTY 0.74%. The standard
  Bulgarian layout scrambles instead and lowered English typo conversions to 0.19%.
- **The ambiguity preference only knows Ukrainian and Russian.** With Bulgarian and Ukrainian both
  enabled, Bulgarian `нещо` typed on the English layout became Ukrainian `луна`: both are words, and the
  Ukrainian preference settled a tie it was never presented as settling.
- **Latin layouts are nearly identical to US.** Polish Pro, the default Polish layout, types exactly
  like US, so there is nothing to detect. German differs only on y/z and the umlaut keys; French AZERTY
  moves a, q, z, w and m. The value of a Latin language depends entirely on its layout.

## What Changes

- **Detection runs over the languages the user has enabled, from a set the app supports.** A language
  is supported only when it has its per-language knowledge (vowels, a dictionary self-test, a
  short-word list) and every realistic two- and three-language combination containing it has cleared
  the measurement bar. First batch: **Bulgarian, German, French**, alongside English, Ukrainian and
  Russian.
- **BREAKING:** an enabled layout whose language is not supported no longer takes part in automatic
  detection. Today such a language is consulted on the dictionary alone, unmeasured. The manual trigger
  still cycles through it, and the debug log says once why it was skipped.
- **The ambiguity preference becomes a choice among the user's languages.** The popup lists the enabled
  supported languages plus "do not convert", and the preference settles a tie only when it is one of
  the tied languages. Existing values `uk`, `ru` and `off` keep their meaning, and the default stays
  Ukrainian.
- **The gibberish rescue settles ties the same way**, instead of accepting only the Ukrainian/Russian
  pair, but only between languages of the same script.
- **A layout that transliterates Latin into another script is not an automatic-fix target** for the
  newly supported languages (Bulgarian Phonetic today). It remains the current layout's language when
  active, and the manual trigger reaches it. Russian Phonetic and Ukrainian QWERTY keep today's
  behaviour; their measured cost is recorded here for a separate decision.
- **A combination measurement** runs every two- and three-language combination of the supported set
  through the real dictionaries and layouts, and gates admission of a language.
- **Declined, with the measurement kept:** Polish (no benefit on its default layout) and Serbian
  (no macOS dictionary, and declined on Windows for its English typo cost).
- **Belarusian, conditional.** It becomes a candidate for admission only once a dictionary source
  clears both a technical check and a licence decision (see below). If it does, it goes through the
  same combination gate as every other language.
- **Kazakh, blocked on a dictionary**, with the layout work it will need written down so it is not
  rediscovered.

## Belarusian and Kazakh

Both have a macOS layout ("Byelorussian", "Kazakh") and neither has a macOS spell checker. Asked about
either language, `NSSpellChecker` calls every string valid, keyboard mash included, so the app already
skips them: the spell checker does not list them.

**Belarusian is blocked only by where its dictionary comes from.** Precision looks affordable: the
Windows collision matrix put `be→ru` at 4.7% and `ru→be` at 4.6%, below the 14.2% `ru→uk` already
shipped. Its layout is ЙЦУКЕН with `ў` and `і` where Russian has `щ` and `и`, so most Belarusian
words tie with Russian or Ukrainian. The Windows port declined Belarusian partly because a third
ЙЦУКЕН language needed the tie logic rewritten; this change already resolves any same-script tie by
the preference, so that blocker is gone. What remains is the dictionary: the LibreOffice `be_BY`
dictionary is CC BY-SA 4.0 or LGPLv3 with no permissive option, which the Windows port declined to
bundle in an MIT app.

Two ways to get a dictionary to the app without bundling it were considered:

- **A user-installed Hunspell dictionary, read by the macOS spell checker.** Tested 2026-09-28 on
  macOS 27 with the Serbian Hunspell files the Windows port once bundled, because macOS has no Serbian
  checker of its own. The files were copied into `~/Library/Spelling` as `sr` and as `sr_RS`, and the
  spell server was restarted each time. Serbian never appeared in `availableLanguages`, and
  `checkSpelling` still accepted mash. Either this route no longer works on current macOS, or it needs
  a logout or enabling the language in Keyboard settings, which was not tried. **Unproven, and not
  relied on.**
- **The app's own Hunspell reader on macOS**, as the Windows port already has, loading a dictionary
  the user downloads on request. Technically certain, since the Windows port does it. It adds a native
  dependency to the Mac app and leaves the licence question to decide, even though the dictionary is
  not in the app bundle.

**Kazakh is blocked on a dictionary.** No freely licensed Kazakh Hunspell dictionary was found when
the Windows port searched LibreOffice and the common repackagers, and its user case is the strongest
of any language considered. Its layout also needs work of its own. The macOS Kazakh layout matches
Russian on every letter key, and its nine extra letters sit on the digit row: `2`→`ә`, `3`→`і`,
`4`→`ң`, `5`→`ғ`, `8`→`ү`, `9`→`ұ`, `0`→`қ`, `-`→`ө`, `=`→`һ`. So between Kazakh and Russian a wrong
layout usually changes nothing on screen, only the layout. And Kazakh typed on the English layout
arrives with digits inside the word (`с2лем` for `сәлем`), which the soft gates would veto before any
dictionary is asked. Supporting it would need the core to treat digit keys as letters for languages
whose layouts put letters there.

## Capabilities

### New Capabilities

None. The behaviour belongs to existing capabilities.

### Modified Capabilities

- `layout-switching-and-language-detection`: layout discovery admits only supported languages;
  transliterating layouts are not automatic targets for newly supported languages; admission of a
  language is gated by the combination measurement.
- `automatic-conversion-on-word-boundaries`: the ambiguity preference and the rescue's tie rule apply
  to ties among any of the user's languages, not only Ukrainian and Russian.
- `settings-and-exception-management`: the ambiguous-word preference offers the enabled supported
  languages instead of a fixed Ukrainian/Russian pair.

## Impact

- **Core** (`Sources/Switcher3wCore/`): the resolver's candidate set, tie handling in `evaluate` and the
  rescue, `resolveAmbiguity`; `ShortWords` gains Bulgarian, German and French lists; `Layout` gains a
  transliteration flag.
- **App** (`Sources/Switcher3w/`): `CoreAdapters` (vowels, canaries, supported set, transliteration
  detection), the Auto-fix preference popup, `SettingsManager` validation of the stored preference, the
  caret flag table.
- **Tests:** a combination measurement replacing the draft `BulgarianCostTests`; prose corpora and
  short-word fixtures for the new languages.
- **Windows:** `ShortWords.cs` is generated from the Swift file, so regenerating it gives the Windows
  Bulgarian build a short-word list it currently lacks. No other Windows change.
- **Docs:** the user guides describe which languages and layouts are supported and why phonetic
  layouts are not auto-fixed.
- **Belarusian, only if its gate clears:** a way to supply a dictionary the macOS spell checker lacks,
  which is either proven to work through the system spell checker or is a Hunspell reader in the app.
  Its licence decision is recorded before any code for it is written.

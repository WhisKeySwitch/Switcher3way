## Why

A Ukrainian user stopped using the app and went back to a competitor. Her report:

> every typo or mistake makes switch to EN from UK. She ended with quite big text with some crap in
> english layout here and there

She is describing the resolver's central assumption, which has been wrong since the fork began. The
reasoning is: this is not a word in the language you are typing, but it *is* a word in another one,
therefore your keyboard is wrong. That argument has no way to express the far more common explanation
— you are writing your own language and you missed a key — so it converts typos, and takes the layout
with it, and the rest of the sentence lands in the wrong alphabet until the user notices.

Measured against natural Ukrainian prose with realistic single-edit typos, **2.9% of typos were
converted** (1.0% with only en+uk installed). At one fumble every eight words that is a corrupted word
roughly every three hundred, plus a spurious layout switch each time — exactly "crap here and there"
across a long document. Two findings explain it:

- **Short words carry almost no information.** 160 of the 676 two-letter Latin strings are in the
  English dictionary — `ft`, `bf`, `kw`, `lb`, `st`, `cg` — mostly abbreviations nobody types as words.
  So a mistyped two-letter Ukrainian word has roughly a one-in-four chance of "being English".
  Measured directly: **13.4% of short Ukrainian typos were converted.**
- **Ukrainian typos land in Russian constantly.** `програма`→`программа`, `адже`→`даже`,
  `колегами`→`коллегами` are all real Russian words. For a Ukrainian user, being silently switched into
  Russian is worse than being switched into English, and word length does not help: these are long.

## What Changes

Weigh how much the dictionary hit is actually worth before acting on it, using two pieces of evidence
the resolver already had access to and never consulted.

- **Ask whether it is a typo first.** Before accepting "this is a word in another language", check
  whether the language *already being typed* holds a word one keystroke away (`TypoGuard.NearMiss`,
  Damerau–Levenshtein distance one over the dictionary's own `TRY` alphabet). A missed key is a simpler
  explanation than a keyboard that changed for one word and changed back.
- **Only trust that test where it discriminates.** It asks whether *any* one-edit neighbour is real,
  and a word has roughly (alphabet × 2 × length) neighbours — about 300 for a four-letter Ukrainian
  word — so on short words it fires on everything. Measured against genuine wrong-layout typing it
  cries wolf on 100% of two-letter words, 30–40% of four-letter ones, and **0% from six characters up**,
  in both directions. Six is therefore where it is consulted.
- **Let the phrase decide the words that are too short to decide themselves.** Below six characters the
  resolver returns the language the surrounding phrase has settled into, if any; contradicting a settled
  phrase is not enough to overturn it. Below four, with nothing settled, it returns the new
  `Outcome.Defer` — leave the text alone, but remember the keystrokes.
- **A word already valid where it was typed now pins the phrase.** This is the strongest evidence the
  app ever sees about what language a phrase is in, and the engine was recording it as `Neutral` and
  throwing it away.
- **Held words are not lost.** A deferred word is recorded as defaulted to the current language, so the
  existing phrase-correction machinery converts it along with the word that finally settles the phrase.
  And when *no* word is long enough to settle anything — a chat message like `як ти?` — a run of two
  held words agreeing on the same language settles it between them. Words only accumulate there while
  nothing in the phrase validates in the layout being typed in, which is what wrong-layout typing looks
  like, so the run is evidence in a way that no single word in it is.
- The manual trigger is unaffected: it asks for the unguarded reading, because an explicit request is
  entitled to an answer even for a two-letter word.

## Both ports

The defect was reported against Windows and is structural, so it was in the macOS resolver too —
`Sources/Switcher3wCore/NWayResolver.swift` had the identical shape (`if current.isValid { return
.keep }`, then any other language wins). Both are fixed, with the same two thresholds and the same
outcomes, named to stay legible side by side: `Outcome.Defer`/`Outcome.held`,
`KeepReason`/`NWayResolver.KeepReason`, `TypoGuard.NearMiss`/`TypoGuard.nearMiss`.

They differ in one place, because the platforms differ. The near-miss check needs the language's
letters; Windows reads them from the Hunspell dictionary's own `TRY` line, and `NSSpellChecker`
publishes nothing equivalent, so the macOS adapter derives them from the keyboard layout of that
language — a language's letters are the letters its layout types, which is if anything the more
direct answer.

## Impact

Measured on the same natural-prose corpora, before and after:

| | before | after |
|---|---|---|
| Ukrainian typos converted (en+uk+ru) | 2.86% | **0.00%** |
| English typos converted (en+uk+ru) | 2.19% | **0.00%** |
| Short Ukrainian typos converted | 13.4% | **0.00%** |
| Paragraph typed in the wrong layout, words left wrong | 0 | **0** |
| Ukrainian paragraph, 1 fumble in 8: words mangled | 1 | **0** |
| …and spurious layout switches | 8 | **0** |

Recall is unchanged where it matters. Deferring short words looks catastrophic when each word is judged
alone — isolated-word recall falls from ~96% to ~52% — and costs nothing over a paragraph, because the
word that settles the phrase converts the held ones with it. That gap is the whole reason this change
is measured in sequences rather than in single words.

**What is genuinely given up:** a single short word typed in the wrong layout, with nothing before or
after it to settle the phrase and no second word to agree with, is no longer auto-converted. The manual
trigger still converts it. This is deliberate — that case is indistinguishable from a typo on the
evidence available, and the app now declines rather than guesses.

`NearMiss` costs 0.04–0.6 ms when it fires and 4–7 ms when it does not, on the engine's worker thread.
The asymmetry falls the right way: a miss means "go ahead and convert", so it is always followed by a
rewrite costing hundreds of milliseconds.

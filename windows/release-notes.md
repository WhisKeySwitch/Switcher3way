Switcher3way for Windows — direct-download preview. If you can use the
[Microsoft Store version](https://apps.microsoft.com/detail/9MXFXL7GG3C5), prefer it: it is signed by
Microsoft, needs no prerequisite, and updates itself.

**This release stops the app converting your typos.** If you write Ukrainian or Russian and have ever
watched a mistyped word jump into English — taking the keyboard layout with it, so the rest of the
sentence came out in the wrong alphabet — this is the fix. Update.

## Fixed — a fumbled key is no longer read as the wrong keyboard

A user went back to a competitor over this, and they were right to:

> every typo or mistake makes switch to EN from UK … quite big text with some crap in english layout
> here and there

The app used to reason: this is not a word in the language you are typing, but it *is* a word in
another one, so your keyboard must be wrong. That reasoning has no way to express the far more common
explanation — you are writing your own language and you missed a key. So it converted typos, moved the
layout, and left English debris scattered through a long document.

Two things were going wrong, and both are now measured rather than assumed:

- **Short words carried no information.** 160 of the 676 possible two-letter Latin strings are in the
  English dictionary — `ft`, `bf`, `kw`, `lb` — almost all abbreviations nobody types as a word. A
  mistyped two-letter Ukrainian word therefore had roughly a one-in-four chance of "being English".
- **Ukrainian typos land in Russian constantly.** `програма` → `программа`, `адже` → `даже`,
  `колегами` → `коллегами` are all real Russian words, and they are long, so no rule about word length
  could have caught them.

What the app does now:

- **It asks whether it is a typo first.** Before accepting that a word belongs to another language, it
  checks whether the language you are already typing holds a real word one keystroke away — a dropped
  letter, a doubled one, a wrong one, two letters swapped. If it does, the simpler story is that you
  missed a key, and the word is left alone.
- **It refuses to judge very short words on their own**, and uses the sentence around them instead. A
  two- or three-letter word is held, untouched, until a longer word settles which language you are
  writing; then it is converted along with it. In a message where every word is short — `як ти?` —
  two words agreeing with each other settle it between them.
- **Correcting a whole sentence typed in the wrong layout still works exactly as before.** This was the
  hard part: measured one word at a time the new caution looks ruinous, and measured across a paragraph
  it costs nothing, because the held words are picked up by the word that resolves the sentence.

Measured over natural prose with realistic typos: the share of typos converted went from **2.9% to 0%**,
spurious layout switches from 8 per page to **none**, and correcting text typed in the wrong layout is
unchanged.

One deliberate trade: a **single short word** typed in the wrong layout, with nothing around it and no
second word to agree with, is no longer corrected automatically — on the evidence available it cannot be
told apart from a typo, so the app declines instead of guessing. The trigger still converts it.

## Fixed — a conversion that does not land is now undone, not reported as done

The rewrite already checked that the replacement it typed had arrived. It did not check that the text it
was replacing had actually *gone* — so a replacement that landed correctly *beside* the old text passed
as a success. Removal is now verified by position as well as content, and the two failures are told
apart, because they need opposite repairs: text that landed wrong is erased and the original restored,
while text that landed beside the original has only the insertion removed. Nothing you can see changes
unless a rewrite fails; when one does, you get your text back instead of a mess built on top of it.

## Also

- The debug log now records **every** decision, including the decision to leave a word alone, with the
  reason. Leaving text untouched is this app's most common action and it looks identical to the app not
  running — which made the typo guard impossible to verify by watching the screen.

## Install

1. Install the [Windows App Runtime 1.6](https://aka.ms/windowsappsdk/1.6/latest/windowsappruntimeinstall-x64.exe)
   once — this channel needs it. The app tells you if it is missing. **.NET is bundled**; you do not
   need to install it.
2. Download the MSI below and double-click it, then approve the **User Account Control** prompt.
3. This build is not code-signed, so SmartScreen will warn — **More info → Run anyway**.
4. Launch **Switcher3way** from the Start menu. It lives in the notification area; Windows 11 hides new
   tray icons, so expand it with the **^** chevron if you cannot see the flag.
5. **Add a second keyboard layout** if you have not: Settings → Time & language → Language & region →
   Add a language → **Ukrainian** or **Russian**. Switcher3way converts *between* the layouts Windows
   has installed, so with only one there is nothing for it to convert between — the app tells you so
   rather than sitting silent.

## Verify the download

SHA-256 of `Switcher3way-0.4.0-win-x64.msi`:

```
8a33baacd6c0d13658abee3923cab8020c3bc25e022c26578350343799be7bfa
```

```powershell
(Get-FileHash .\Switcher3way-0.4.0-win-x64.msi -Algorithm SHA256).Hash
```

The in-app updater checks this same checksum before installing anything.

## Known limitations

- **Not code-signed** — SmartScreen warns on first run. The Store build is signed by Microsoft.
- **x64 only.** No arm64 build yet.
- **Cannot rewrite text inside windows running as administrator** unless Switcher3way is also running
  as administrator — Windows blocks synthesized input from a lower integrity level. The app reports
  this rather than silently doing nothing.
- Password fields are deliberately excluded from processing.
- Replacing a very long selection — near the 200-character limit — still takes a few seconds, because
  erasing the old text remains one keystroke per character. Going faster was tried and measured, and
  every faster method lost keystrokes; the delay is what the receiving application needs.
- In applications that expose no text to accessibility tools, the app cannot check its own work. It
  says so in the debug log and behaves as before rather than guessing.

Free and open source under the MIT License — https://github.com/WhisKeySwitch/Switcher3way

Switcher3way for Windows — direct-download preview. If you can use the
[Microsoft Store version](https://apps.microsoft.com/detail/9MXFXL7GG3C5), prefer it: it is signed by
Microsoft, needs no prerequisite, and updates itself.

**More of your wrong-layout words get fixed, and fewer of your conversions get quietly lost.** This is
the largest correctness release since the app went to the Store — most of it found by reading twelve
days of real logs rather than by testing ideas.

## Fixed — a spell checker that answers wrong is no longer believed

A whole line typed in the wrong layout would sometimes stay unconverted, and the log showed something
impossible: the app's own record saying a word *is* a valid Ukrainian word, next to a verdict saying
no language recognised it.

The spell checker goes through brief spells of answering wrong — real words rejected, keyboard mash
accepted — and the app was asking it about the same word twice while making one decision. When the two
answers disagreed, the conversion vanished with no sign that anything had happened.

It now checks the answer it is about to act on, at the moment of acting, and stops trusting a
dictionary that has just contradicted itself. If you have ever typed a line, watched nothing happen,
and shrugged — this was often why.

## Fixed — six reasons wrong-layout words were being left alone

From 5,731 automatic decisions across twelve days. Each was found, measured, and either fixed or
deliberately left off with the number written down:

- **Short words were being second-guessed too eagerly.** The check that protects you from having typos
  "corrected" was running on four- and five-letter words, where almost every string resembles some
  real word. All 26 words it held back there were genuine, and not one was a typo.
- **Meaningless tokens were deciding the language of your sentence.** `10`, `.`, `e` — a token with no
  letters in it now settles nothing.
- **`You're`, `That's` and `Кто-то`** were skipped because of an apostrophe or a hyphen.
- **A Russian word typed on the Ukrainian layout** now switches the layout, without retyping your text,
  once the sentence makes the language clear.
- Two more, including one measured, found imperfect, and shipped **off** rather than shipped hopeful.

## New — Bulgarian

Bulgarian joins English, Ukrainian and Russian. Add the Bulgarian keyboard in Windows and it works the
same way: type Bulgarian with the wrong layout active and the app puts it right.

## Also

- The rescue for words no dictionary knows no longer accepts a word ending in four consonants.
  `Шкудфтв` — *Ireland* typed on a Russian layout — used to slip through.
- Tapping the trigger offers the right layout as one step rather than two.

## Install

1. Install the [Windows App Runtime 1.6](https://aka.ms/windowsappsdk/1.6/latest/windowsappruntimeinstall-x64.exe)
   once — this channel needs it. The app tells you if it is missing. **.NET is bundled**; you do not
   need to install it.
2. Download the MSI below and double-click it, then approve the **User Account Control** prompt.
3. This build is not code-signed, so SmartScreen will warn — **More info → Run anyway**.
4. Launch **Switcher3way** from the Start menu. It lives in the notification area; Windows 11 hides new
   tray icons, so expand it with the **^** chevron if you cannot see the flag.
5. **Add a second keyboard layout** if you have not: Settings → Time & language → Language & region →
   Add a language → **Ukrainian**, **Russian** or **Bulgarian**. Switcher3way converts *between* the
   layouts Windows has installed, so with only one there is nothing for it to convert between.

## Verify the download

SHA-256 of `Switcher3way-0.6.0-win-x64.msi`:

```
832842c185e1b5d0d9ed44d86367159aef6981ae321ee6e3e5b949edc5f2ec7c
```

```powershell
(Get-FileHash .\Switcher3way-0.6.0-win-x64.msi -Algorithm SHA256).Hash
```

The in-app updater checks this same checksum before installing anything.

## Known limitations

- **Not code-signed** — SmartScreen warns on first run. The Store build is signed by Microsoft.
- **x64 only.** No arm64 build yet.
- A word finished with **Enter or Tab** is not auto-converted: the app cannot re-type those
  characters, so rather than attempt a replacement that cannot land it leaves the word alone. The
  trigger still converts it.
- **Cannot rewrite text inside windows running as administrator** unless Switcher3way is also running
  as administrator — Windows blocks synthesized input from a lower integrity level.
- Password fields are deliberately excluded from processing.
- Replacing a very long selection — near the 200-character limit — still takes a few seconds, because
  erasing the old text remains one keystroke per character.
- In applications that expose no text to accessibility tools, the app cannot check its own work. It
  says so in the debug log and behaves as before rather than guessing.

Free and open source under the MIT License — https://github.com/WhisKeySwitch/Switcher3way

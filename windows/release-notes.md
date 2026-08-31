Switcher3way for Windows — direct-download preview. If you can use the
[Microsoft Store version](https://apps.microsoft.com/detail/9MXFXL7GG3C5), prefer it: it is signed by
Microsoft, needs no prerequisite, and updates itself.

**Words no dictionary knows now get converted too.** Until this release, a name or a piece of jargon
typed in the wrong layout stayed as gibberish and had to be fixed by hand.

## New — names and jargon typed in the wrong layout

The app decided what to convert by asking a dictionary: if the keystrokes spell a real word in
another language, they were meant for that language. That rule is exactly right for ordinary words
and exactly wrong for everything a dictionary has never heard of — product names, tech jargon, proper
nouns. `Kyiv` typed while the Ukrainian layout is active comes out as `Лншм`, and no dictionary
anywhere validates either form, so nothing happened. Every such word cost you a manual fix.

The signal the app was missing is **shape, not vocabulary**. A word typed in the wrong layout is not
merely unknown — it is unpronounceable in the language it landed in, while exactly one of the
alternatives is a perfectly ordinary word shape for its own language. `Лншм` is not a possible
Ukrainian word; `Kyiv` is an entirely normal English one. That asymmetry is what a person spots
instantly, and the app now checks it.

So when no dictionary recognises a word in any language, the app looks at its shape instead, and
converts only when exactly one language could plausibly have produced it.

**What deliberately still keeps.** This is a weaker signal than a dictionary match, so everything
that guarded conversion before guards it here too — and the thresholds were chosen by measuring
against real words that must not move, not by taste. `Kyiv` typed *in* the English layout, `PeopleOps`,
`SSO`, `npm`, code identifiers and vowel-less abbreviations like `хз` all stay exactly as you typed
them. Verified end to end on this build: five such words, zero touched.

A rescued word is also held more loosely than a dictionary match — it will not decide what language
the rest of your sentence is in, and a later word can still correct it.

**A note for Ukrainian and Russian typists.** On Windows this mostly helps in one direction. The
dictionaries shipped with the app already know a good deal of Ukrainian and Russian vocabulary, so
jargon like `апка` or `тенанту` was usually converted already. What was not handled — and now is —
are Latin names and terms typed while a Cyrillic layout is active.

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

SHA-256 of `Switcher3way-0.5.0-win-x64.msi`:

```
8fab71fcf78f01f49d7ec2740cfa05ff6751d731922de2192b2f2b222b2f1cfd
```

```powershell
(Get-FileHash .\Switcher3way-0.5.0-win-x64.msi -Algorithm SHA256).Hash
```

The in-app updater checks this same checksum before installing anything.

## Known limitations

- **Not code-signed** — SmartScreen warns on first run. The Store build is signed by Microsoft.
- **x64 only.** No arm64 build yet.
- A word finished with **Enter or Tab** is not auto-converted: the app cannot re-type those
  characters, so rather than attempt a replacement that cannot land it leaves the word alone. The
  trigger still converts it.
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

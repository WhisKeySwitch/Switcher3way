Switcher3way for Windows — direct-download preview. If you can use the
[Microsoft Store version](https://apps.microsoft.com/detail/9MXFXL7GG3C5), prefer it: it is signed by
Microsoft, needs no prerequisite, and updates itself.

This release fixes text loss. If you use the trigger on selected text, update.

## Fixed — the trigger could erase text it never looked at

- **Converting a selection could delete more than you selected**, including text on the line above it.
  The app erases the text it recorded you typing; if the cursor had moved since — you pressed an arrow
  key, Home, or End, or selected with Shift+arrows — it erased that many characters wherever the cursor
  now was. Everything buffered is now discarded the moment the cursor moves, so a conversion can only
  rewrite the words it actually saw you type.
- **Select-all then trigger could replace the whole document.** `Ctrl+A` was being recorded as if you
  had typed the letter "a", so the trigger converted that "a" — and its first backspace took the entire
  selection with it. Keyboard shortcuts are no longer mistaken for typing. This also stops `Alt+Tab`
  from finishing a word behind your back.
- **When text is selected, the trigger now always converts the selection** rather than the last word
  you typed. What it changes is what you highlighted.

## New since 0.2.7

- **The trigger always answers.** When it cannot convert anything — only one keyboard layout installed,
  nothing typed or selected, the text already correct, a selection over 200 characters — it now says so
  in a small chip next to the cursor as well as a notification, instead of appearing dead.
- The debug log records why a conversion did nothing, and whether reading a selection succeeded, so
  "it did nothing" is diagnosable instead of silent.

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
   has installed, so with only one there is nothing for it to convert between — the app now tells you
   so rather than sitting silent.

## Verify the download

SHA-256 of `Switcher3way-0.2.9-win-x64.msi`:

```
dca9a645695976d7aa5852ae80a71a94625f8955d2d608f9dd8210f64aa51ac4
```

```powershell
(Get-FileHash .\Switcher3way-0.2.9-win-x64.msi -Algorithm SHA256).Hash
```

The in-app updater checks this same checksum before installing anything.

## Known limitations

- **Not code-signed** — SmartScreen warns on first run. The Store build is signed by Microsoft.
- **x64 only.** No arm64 build yet.
- **Cannot rewrite text inside windows running as administrator** unless Switcher3way is also running
  as administrator — Windows blocks synthesized input from a lower integrity level. The app reports
  this rather than silently doing nothing.
- Password fields are deliberately excluded from processing.
- Cycling a converted selection past a full loop of layouts can corrupt the text on the fourth trigger
  press. Diagnosed and being fixed; until then, a selection you have cycled all the way back to the
  original is best left alone.

Free and open source under the MIT License — https://github.com/WhisKeySwitch/Switcher3way

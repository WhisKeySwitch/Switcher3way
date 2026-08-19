Switcher3way for Windows — direct-download preview. If you can use the
[Microsoft Store version](https://apps.microsoft.com/detail/9MXFXL7GG3C5), prefer it: it is signed by
Microsoft, needs no prerequisite, and updates itself.

This release fixes a conversion that could damage text while reporting success. If you use the trigger
on selected text, update.

## Fixed — a conversion that landed wrong looked like one that worked

- **Cycling a selection through the layouts could corrupt it.** Convert a selected phrase, tap again for
  the next layout, tap again to come back — and the text could return mangled, with runs of characters
  replaced by whichever character followed them. Worse, the app believed it had succeeded, so every
  further tap converted the damage instead of the original.
- **The app now checks its own work.** After replacing text it reads back what actually landed and
  compares it with what it meant to write. A replacement that does not match is reported as a failure,
  the previous text is put back, and the cycle stops rather than building on a bad result.
- **Long replacements are pasted, not typed.** Inserting a long phrase one keystroke at a time was both
  the cause of the corruption and the reason it was slow: replacing a sentence took a second and a half,
  and a 200-character selection took six seconds. It is now a single paste — about twice as fast, and
  reliable. Your clipboard is borrowed for that instant and handed straight back; short conversions
  still type, and never touch it.
- **The trigger no longer converts text you did not select.** It asked the system for the selection by
  copying, and treated any change to the clipboard as proof that its copy had worked — so another
  program writing to the clipboard at the wrong moment could feed it text you never highlighted, which
  it would then convert and type at the cursor.

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

SHA-256 of `Switcher3way-0.3.0-win-x64.msi`:

```
87bb55246d58b2c12f51fd55a8e5cf285af8b705f5fee7abc3b70381f6d8276a
```

```powershell
(Get-FileHash .\Switcher3way-0.3.0-win-x64.msi -Algorithm SHA256).Hash
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
  erasing the old text remains one keystroke per character.
- In applications that expose no text to accessibility tools, the app cannot check its own work. It
  says so in the debug log and behaves as before rather than guessing.

Free and open source under the MIT License — https://github.com/WhisKeySwitch/Switcher3way

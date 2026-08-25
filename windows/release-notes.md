Switcher3way for Windows — direct-download preview. If you can use the
[Microsoft Store version](https://apps.microsoft.com/detail/9MXFXL7GG3C5), prefer it: it is signed by
Microsoft, needs no prerequisite, and updates itself.

**This release stops the app interrupting you at the end of every line**, and stops it blaming a
problem it had not diagnosed. If you finish sentences with Enter — which is to say, if you type —
update.

## Fixed — the app no longer attempts a conversion it cannot complete

Finishing a word with **Enter** could never be converted. Not since the app was written. What
happened instead was that it tried: erased your word, typed the replacement, discovered the result
was wrong, put your text back, and told you the window "may be running as administrator". Every line.

The cause is small and complete. When the app converts a word it replaces the word *and the character
that ended it*, and it types every character as a Unicode code point. That is exactly right for a
space and useless for Enter — a Windows text box ignores it — so the replacement always arrived one
character short and the check added in 0.4.0 correctly refused it.

This was never a working feature that broke. It only became *visible* in 0.4.0, when the app started
reading back what it had written: before that the same rewrite reported success and left your text
however it fell.

So the app now declines. A word finished with Enter or Tab is left alone, quietly. Nothing you see
changes — it was never converted either way — but the rewrite that ran, failed, undid itself and
interrupted you is gone. Words finished with a space convert exactly as before, and the trigger is
unaffected.

Re-pressing Enter to put the line break back was considered and rejected: it would work in a text
editor and misfire in a chat box, where Enter has already sent the message and pressing it again
would send another. Nothing tells those apart in advance, so the app does not guess.

## Fixed — failure messages that describe what actually failed

Every rewrite failure was reported as *"Can't change text in this window — it may be running as
administrator."* That is true for exactly one of them. A conversion refused in an ordinary text editor
sent you looking for elevation you do not have, while the real behaviour — the app checked its own
work, disliked the result, and put your original back — went unmentioned.

A conversion that does not land now says so, and says your text was put back. Administrator rights
are named only when that is genuinely the cause.

## Fixed — settings that cannot be read are no longer discarded in silence

If the settings file could not be read — a truncated write after a crash, a disk error, a file from a
newer version — the app quietly started with defaults and then saved them over the top, usually within
seconds of launching and without you touching anything. Your exception lists, denied apps, trigger key
and language preference were gone, with nothing said and nothing logged, because the debug-log switch
that would have recorded it lives in the file that failed to load.

The unreadable file is now kept as `settings.json.bad`, the failure is recorded whatever the log
setting says, and you are told.

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

SHA-256 of `Switcher3way-0.4.1-win-x64.msi`:

```
1b17870d50f2b3d5ae9ba02142a9c0d53395251385c66c4eb16250687363f9b0
```

```powershell
(Get-FileHash .\Switcher3way-0.4.1-win-x64.msi -Algorithm SHA256).Hash
```

The in-app updater checks this same checksum before installing anything.

## Known limitations

- **Not code-signed** — SmartScreen warns on first run. The Store build is signed by Microsoft.
- **x64 only.** No arm64 build yet.
- A word finished with **Enter or Tab** is not auto-converted, for the reason above. The trigger still
  converts it if the text is still on screen.
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

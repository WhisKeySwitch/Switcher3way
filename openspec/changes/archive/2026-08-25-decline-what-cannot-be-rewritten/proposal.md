## Why

A word finished with **Enter** has never been converted successfully, and the app has been trying
anyway — running a rewrite, failing verification, undoing itself, and raising a notification, every
time. Found in a real user's log, twice on the same word:

```
auto: "ьукпув" -> "merged" : Mismatch
rewrite: MISMATCH — wanted "merged\n", landed "\nmerged"
rewrite: repaired back to "ьукпув\n"
notify: Can't change text in this window — it may be running as administrator.
```

Reproduced in Notepad, where the cause is unambiguous:

```
rewrite: erased 7 in 103 ms
rewrite: MISMATCH — wanted "привіт\n", landed "привіт"  [caret 7 -> 6, expected 7]
```

The rewrite erases the word **and its boundary**, then re-types both — and it types every character
as a Unicode code point. That is correct for a space and useless for Enter: a Windows edit control
ignores U+000A. Carrying U+000D instead was tried and measured; it is ignored too. The replacement
therefore always lands one character short, and the read-back added in 0.4.0 correctly refuses it.

So this is not a new defect. It is an old one that only became visible when the app started checking
its own work — before 0.4.0 the same rewrite reported success and left the text however it fell.

## What Changes

**The app declines to convert a word whose boundary it cannot reproduce**, rather than attempting a
rewrite that cannot succeed.

Re-emitting the boundary as a key press instead was considered and rejected. It would fix a text
editor and break a chat box: there, Enter already sent the message, and pressing it again would send
another. Nothing available before the rewrite distinguishes "Enter inserts a line break" from "Enter
submits", and the second is not a mistake worth risking to save the first.

What the user sees does not change — the word was never converted either way. What stops is the
rewrite that runs, fails, undoes itself and interrupts them, at the end of every line.

## Impact

- Words finished with Enter or Tab are no longer auto-converted. They never were; the attempt merely
  failed noisily. The manual trigger is unaffected, and a word finished with a space converts exactly
  as before — verified in the same run.
- One fewer misleading notification, on top of the messages corrected alongside this: every rewrite
  failure used to be reported as "this window may be running as administrator", true for exactly one
  of them and plainly wrong for a Mismatch in an ordinary text editor.

## What this does not fix

The **manual trigger** on a hard-boundary word, and the case where Enter has already submitted the
text so there is nothing left on screen to rewrite. Neither is made worse here.

# Reply to Store certification — 10.1.2.10 Functionality (second report)

Product ID **9MXFXL7GG3C5** · "Unusable Feature: Trigger - None of the trigger options are funtional",
observed on a Surface Go 4, OS build 26.200.8457.

Paste as the certification reply / resubmission note.

---

**Subject:** Switcher3way (9MXFXL7GG3C5) — resubmission: root cause found and fixed

Thank you — the second report gave us what we needed, and the tester found a real defect.

**Root cause.** Switcher3way watches keystrokes with a low-level keyboard hook. To avoid reacting to the
corrections it types itself, it ignored every keystroke Windows marks as injected. That mark is also set
by the **on-screen touch keyboard**, Remote Desktop and accessibility tools — so on a Surface Go 4 used
as a tablet, the app never received a single keystroke. Nothing reached its word buffer, the trigger
press itself was invisible to it, and so every trigger option did nothing. The tester's steps were
correct and the conclusion was correct.

**Fix.** The app now marks its own synthesized keystrokes and ignores only those. Input from the
on-screen keyboard, Remote Desktop and automation is treated as ordinary typing. We reproduced the
reported steps using injected input before and after the change: before, the app logged no keystrokes at
all; after, it receives the typed word and the trigger.

**Second improvement in the same submission.** If the trigger has nothing to convert, it now says so
instead of doing nothing. On a PC with a single keyboard layout it shows: *"Add a second keyboard layout
— Switcher3way converts between the keyboard layouts Windows has installed, and there is only one it can
use."* Previously that situation was silent, which is indistinguishable from a broken feature.

**How to verify (about two minutes).**

1. **Add a second keyboard layout** — Settings → Time & language → Language & region → Add a language →
   **Ukrainian** (or Russian), alongside English. Switcher3way converts a word from one installed layout
   to another, so with a single layout there is nothing for it to convert between. *If this step is
   skipped, the app will now tell you so rather than appearing dead.*
2. Start Switcher3way. It runs in the notification area and has no main window; a short welcome flow
   appears on first launch. Windows 11 hides new tray icons — expand the notification area with the "^"
   chevron if the icon is not visible.
3. Open Notepad. With the **English** layout active, type `ghbdsn` and press the spacebar. The text is
   replaced with `привіт` and the layout switches to Ukrainian.
4. Or select text typed in the wrong layout and tap **Ctrl twice**; it converts in place, and tapping
   again cycles the other layouts and restores the original.

Any keyboard works for these steps, including the on-screen one.

`runFullTrust` is unchanged: a system-wide keyboard hook and `SendInput`, needed to correct text in
whatever application the user is typing in. The app is fully offline, stores nothing, and excludes
password fields. Source: https://github.com/WhisKeySwitch/Switcher3way

Thank you for re-testing.

---

## Notes for us, not for them

- Surface Go 4 was the clue. A tablet with no Type Cover means the touch keyboard, which injects — and
  our hook discarded every injected event. The first report ("no response after a double tap of Ctrl")
  was very likely the same cause, not the single-layout one we assumed.
- Both reports were fair. We shipped an app that could not work on a tablet at all, and gave no feedback
  when it had nothing to do.
- The fix also removes the "a physical keyboard is required" limitation from the docs and store listing,
  and makes the conversion path testable without a human at the keyboard.

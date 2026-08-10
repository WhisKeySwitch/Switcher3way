# Reply to Store certification — 10.1.2.10 Functionality (second report)

Product ID **9MXFXL7GG3C5** · "Unusable Feature: Trigger - None of the trigger options are funtional",
observed on a Surface Go 4, OS build 26.200.8457.

Paste as the certification reply / resubmission note.

---

**Subject:** Switcher3way (9MXFXL7GG3C5) — resubmission: root cause found and fixed

Thank you — the second report identified a real defect, and the tester's steps were correct.

**Root cause.** Switcher3way watches keystrokes with a low-level keyboard hook. To avoid reacting to the
corrections it types itself, it ignored every keystroke Windows marks as synthesized. Windows applies
that mark to far more than an application's own output: input arriving through Remote Desktop, virtual
machines, remote-support tools, keyboard remappers, accessibility input tools and the on-screen keyboard
all carry it. On any of those the app received nothing at all — no keystroke reached its word buffer, the
trigger press itself was invisible to it, and every trigger option therefore did nothing.

**Fix.** The app now marks its own synthesized keystrokes and ignores only those. Everything else is
treated as ordinary typing, which is what it is: someone typing on a physical keyboard into a Remote
Desktop session, or through a remapper, makes exactly the wrong-layout mistakes this app corrects. We
reproduced the reported steps using synthesized input before and after the change: before, the app
logged no keystrokes at all; after, it receives the typed word and the trigger.

**Second improvement in the same submission.** When the trigger has nothing to convert, it now says so
rather than doing nothing. On a PC with a single keyboard layout it shows: *"Add a second keyboard layout
— Switcher3way converts between the keyboard layouts Windows has installed, and there is only one it can
use."* That situation used to be silent, which is indistinguishable from a broken feature and is likely
what the first report encountered as well.

**How to verify (about two minutes).**

1. **Add a second keyboard layout** — Settings → Time & language → Language & region → Add a language →
   **Ukrainian** (or Russian), alongside English. Switcher3way converts a word from one installed layout
   to another, so with a single layout there is nothing for it to convert between. *If this step is
   skipped, the app now tells you so rather than appearing dead.*
2. Start Switcher3way. It runs in the notification area and has no main window; a short welcome flow
   appears on first launch. Windows 11 hides new tray icons — expand the notification area with the "^"
   chevron if the icon is not visible.
3. Open Notepad. With the **English** layout active, type `ghbdsn` and press the spacebar. The text is
   replaced with `привіт` and the layout switches to Ukrainian.
4. Or select text typed in the wrong layout and tap **Ctrl twice**; it converts in place, and tapping
   again cycles the other layouts and restores the original.

These steps work with any input method, including the on-screen keyboard and a remote session.

`runFullTrust` is unchanged: a system-wide keyboard hook and `SendInput`, needed to correct text in
whatever application the user is typing in. The app is fully offline, stores nothing, and excludes
password fields. Source: https://github.com/WhisKeySwitch/Switcher3way

Thank you for re-testing.

---

## Notes for us, not for them

- Surface Go 4 was the clue: a tablet with no Type Cover means the on-screen keyboard, which is
  synthesized — and the hook discarded every synthesized event. The first report ("no response after a
  double tap of Ctrl") was very likely the same cause rather than the single-layout one we assumed.
- **The touch keyboard is the weakest part of the argument and should not lead.** Its keycaps show the
  active layout, so a user cannot type `ghbdsn` believing they are typing `привіт` — the mistake this app
  fixes is a blind-typing one. The real gains are Remote Desktop, virtual machines and remapped
  keyboards, where people type on physical keyboards and do make the mistake. Certification is a gate,
  not a use case.
- Cost of the change, accepted: text expanders, macro tools and password-manager auto-type are now
  visible to the engine. Password fields remain guarded, but injected foreign-language text may be
  corrected. Windows offers no way to distinguish a remote session's keystrokes from an application
  injecting text, so it is accept-all or reject-all — and reject-all failed certification twice.

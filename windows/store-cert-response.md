# Reply to Store certification — 10.1.2.10 Functionality

Product ID **9MXFXL7GG3C5** · report of 08/07/2026 · "Unusable Feature: There is no response after a
double tap of Ctrl."

Paste as the certification reply / resubmission note. Keep it short — reviewers skim, and the testing
steps are the part that matters.

---

**Subject:** Switcher3way (9MXFXL7GG3C5) — resubmission after 10.1.2.10 functionality failure

Thank you for the detailed report — the tester was right, and the silence they saw was our defect.

**Why there was no response.** Switcher3way corrects a word typed in the wrong keyboard layout by
converting it to another layout the user has installed. On a PC with only one keyboard layout there is
nothing to convert between, so the trigger genuinely had nothing to do — and the previous build simply
did nothing at all in that situation, with no message. That is indistinguishable from a broken feature,
so the result was fair.

**What we changed.** In this submission the trigger always responds. When it cannot convert, the app now
shows a notification explaining why and what to do — for example, on a PC with a single keyboard layout:
"Add a second keyboard layout — Switcher3way converts between the keyboard layouts Windows has installed,
and there is only one it can use." The same applies when nothing has been typed yet, or when the text is
already correct for the current layout.

**How to verify (about two minutes).**

1. Add a second keyboard layout: **Settings → Time & language → Language & region → Add a language →
   Ukrainian** (or Russian). This is required — with one layout the app has nothing to convert between.
2. Start Switcher3way. It runs in the notification area and has no main window; a short welcome flow
   appears on first launch. Windows 11 hides new tray icons, so expand the notification area with the "^"
   chevron if the icon is not visible.
3. Open Notepad. With the **English** layout active, type `ghbdsn` and press the spacebar. The text is
   replaced with `привіт` and the layout switches to Ukrainian.
4. Or select any text typed in the wrong layout and tap **Ctrl twice** — it converts in place. Tapping
   again cycles the other layouts and then restores the original.

**One note on automated testing.** The app deliberately ignores synthetic input: it uses a low-level
keyboard hook and would otherwise react to its own corrections. Keystrokes injected by a test harness,
a remote-control tool or the on-screen touch keyboard produce no response by design. Please test by
typing on a physical keyboard.

`runFullTrust` is unchanged and is used only for the system-wide keyboard hook and `SendInput` needed to
correct text in the app the user is typing in. The app is fully offline, stores nothing, and excludes
password fields. Source: https://github.com/WhisKeySwitch/Switcher3way

Thank you for re-testing.

---

## Notes for us, not for them

- The reviewer tested on a Dell Inspiron 5379 and a Microsoft Surface Laptop, OS build 26200.7840 —
  clean machines, so almost certainly a single English layout. That matches the failure exactly.
- The same silence would have hit every new user whose PC has one layout. The report found a real
  usability defect, not just a testing gap.
- Make sure the **Additional Testing Information** page carries the four steps above. The previous
  submission's notes were the likely gap: the prerequisite has to be the first thing a reviewer reads.

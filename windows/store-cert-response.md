# Reply to Store certification — 10.1.2.10 Functionality (third report)

Product ID **9MXFXL7GG3C5** · "Unusable Feature: There is no response after a double tap of Ctrl",
observed on a Surface Laptop 5, OS build 26200.8328, against submission **0.2.7**.

Paste as the certification reply / resubmission note. Resubmission is **0.2.8**.

---

**Subject:** Switcher3way (9MXFXL7GG3C5) — resubmission 0.2.8: the response was being discarded by the Store build

Thank you. The tester saw nothing, and this time we can say exactly why: the app was producing a response
and the Store build was throwing it away.

**Root cause.** When the trigger has nothing to convert — most often because the PC has a single keyboard
layout, and there is then nothing to convert *between* — the app explains that in a Windows notification.
That response never appeared, because in the packaged build the app could not show notifications at all.
`AppNotificationManager.Register()` behaves differently depending on whether the process has package
identity: unpackaged, it creates the notification activator itself; packaged, it *looks the activator up*
in the package's own COM registration, and our package manifest never declared one. Registration
therefore failed at startup and every notification the app would ever show was dropped — silently, since
notification failures are not allowed to stop the tray from working. The result on the tester's machine
was precisely the reported one: a double tap of Ctrl, and nothing.

This is also why our own testing did not catch it. The response was verified on the direct-download
(MSI) build, which is unpackaged and registers its activator at runtime, so it worked there and only
there. The defect existed solely in the Store flavour of the same code.

**Fix, in two parts.**

1. **The manifest now declares the notification activator** (`windows.toastNotificationActivation` plus
   the matching `windows.comServer` entry). Registration succeeds in the packaged build, and every
   notification — the trigger's explanation included — is shown.

2. **The trigger's answer no longer depends on notifications at all.** It now also appears as a small
   chip next to the text cursor, drawn by the app itself: *"Add a Ukrainian or Russian layout"*. A
   notification can be suppressed by things an app does not control — Do Not Disturb, notifications
   turned off — and a suppressed explanation is indistinguishable from a broken feature. The chip cannot
   be suppressed, so the trigger visibly responds in every case.

**Verified in the packaged build this time**, not the unpackaged one. Installed as an MSIX and replayed
the reviewer's step on a PC with one keyboard layout:

- before the fix: `toast: registration failed, notifications disabled: No COM servers are registered for
  this app`, then the trigger's explanation dropped;
- after the fix: `toast: registered`, the notification shown, and the chip drawn next to the cursor.

**How to verify (about two minutes).**

1. **Add a second keyboard layout** — Settings → Time & language → Language & region → Add a language →
   **Ukrainian** (or Russian), alongside English. Switcher3way converts a word from one installed layout
   to another, so with a single layout there is nothing for it to convert between. *If this step is
   skipped, tapping the trigger now tells you so — on screen and as a notification — rather than
   appearing dead.*
2. Start Switcher3way. It runs in the notification area and has no main window; a short welcome flow
   appears on first launch. Windows 11 hides new tray icons — expand the notification area with the "^"
   chevron if the icon is not visible.
3. Open Notepad. With the **English** layout active, type `ghbdsn` and press the spacebar. The text is
   replaced with `привіт`, the layout switches to Ukrainian, and a chip under the word shows the change.
4. Or select text typed in the wrong layout and tap **Ctrl twice**; it converts in place, and tapping
   again cycles the other layouts and restores the original.

These steps work with any input method, including the on-screen keyboard and a remote session.

`runFullTrust` is unchanged: a system-wide keyboard hook and `SendInput`, needed to correct text in
whatever application the user is typing in. The app is fully offline, stores nothing, and excludes
password fields. Source: https://github.com/WhisKeySwitch/Switcher3way

Thank you for re-testing.

---

## Notes for us, not for them

- **Three reports, one lesson: verify in the flavour that ships.** The 0.2.6 hint was verified with
  `diaghint` on the unpackaged payload; the one code path that behaves differently between the two
  flavours was the one that was broken. `diaghint` now goes through the same `Tray.ShowHint` the trigger
  uses, so it exercises both surfaces, and the packaged build is the one to test it on.
- The registry key the SDK reads is
  `HKLM\SOFTWARE\Classes\PackagedCom\Package\{PackageFullName}\Class`; the lookup matches the ExeServer
  whose `Arguments` are exactly the notification-activation switch, and compares the registered
  executable's filename against the running process. Absent that key it throws `E_FAIL` — "No COM servers
  are registered for this app" — which is what our log showed. Source:
  `WindowsAppSDK/dev/PushNotifications/PushNotificationUtility.h`, `GetComRegistrationFromRegistry`.
- The activator CLSID (`A1429C4E-…`) must stay stable across releases and identical in both manifest
  extensions.
- A dropped notification is now logged ungated ("toast: not registered — this and any further
  notifications are dropped"). Without that line the log showed a hint being raised and gave no hint that
  it went nowhere, which is what made this take three cycles to find.
- The injected-input fix from 0.2.7 is unaffected and still correct; it simply was not what report 1 or
  report 3 were about.

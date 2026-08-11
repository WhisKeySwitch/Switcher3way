# Switcher3way — User Guide

*Also available in: [Українська](user-guide.uk.md) · [Русский](user-guide.ru.md)*

Switcher3way notices when you've typed a word in the wrong keyboard layout and fixes it —
retyping the word in the layout you meant and switching the keyboard for you. It works across
**all** your installed layouts (e.g. English, Ukrainian, Russian), not just a pair.

It runs in the **menu bar** on macOS and in the **notification area** on Windows. This guide is
written with the macOS names for menus and settings; the Windows app has the same settings under
the same names, reached from the tray icon.

- [How detection works](#how-detection-works)
- [First launch](#first-launch)
- [The menu bar](#the-menu-bar)
- [Converting by hand: the trigger key](#converting-by-hand-the-trigger-key)
- [Auto-fix: converting as you type](#auto-fix-converting-as-you-type)
- [Exceptions](#exceptions)
- [Settings reference](#settings-reference)
- [Pausing the app](#pausing-the-app)
- [Privacy](#privacy)
- [Troubleshooting & FAQ](#troubleshooting--faq)

## How detection works

When you finish a word, Switcher3way renders the keystrokes you actually pressed through
**every keyboard layout installed on your Mac** that has a macOS dictionary, and checks each
candidate word against its own language's dictionary. Only when exactly **one** candidate is a
valid word does it convert and switch the layout.

This is deliberately **precision-first**: a word that looks like code, is ALL-CAPS, or is very
short is left alone rather than guessed at. A missed fix costs you one trigger tap; a wrong fix
costs you trust.

Words valid in **both Ukrainian and Russian** (`там`, `добре`) get special treatment: they are
converted to the **language for ambiguous words** (Settings → Auto-fix; Ukrainian by default).
If the phrase you're typing later turns out to be the other language — a word appears that's
valid **only** in it — the earlier ambiguous words are re-converted automatically, in one step
you can undo with a single trigger tap. Set the option to *Do not convert* to keep such words
untouched instead.

## First launch

macOS requires two permissions before any layout switcher can work:

| Permission | Why Switcher3way needs it |
|---|---|
| **Accessibility** | To read and retype the mistyped word |
| **Input Monitoring** | To see your keystrokes and the trigger key |

On first launch a **setup checklist** window opens. For each permission, click **Open
Settings**, flip the switch for Switcher3way in System Settings → Privacy & Security, and come
back — the checklist detects the grant by itself within a couple of seconds. After Input
Monitoring is granted, the app restarts itself once (macOS requires it). The same window offers
a **Launch at login** switch.

Closing the window loses nothing: your grants stay, and the checklist can be reopened from the
menu (**Check Permissions…** — the item appears only while something is missing).

> Installed from source? The app is unnotarized, so the very first launch on a new Mac needs
> right-click → **Open**.

## The menu bar

The status icon shows the **flag of the active layout** (🇺🇸 / 🇺🇦 / 🇷🇺 …) and live-tracks
switches made by any means, including the system shortcut. While the app is paused or turned
off, the icon gains a **⏸** prefix — a disabled switcher never looks enabled.

Click the icon to open the menu:

- **Header** — the current layout (badge + name), a reminder of your trigger key, and the app
  version.
- **Quick toggles** — *Auto-fix as I type*, *Layout sound*, *Flag at cursor*. These mirror the
  corresponding switches in Settings.
- **Pause Switcher3way ▸** — see [Pausing the app](#pausing-the-app).
- **Help (⌘?)** — opens this guide right in the app, in your interface language.
- **Settings… (⌘,)** and **Quit (⌘Q)**.

Two optional signals about layout changes (both off by default):

- **Layout sound** — a short sound on the first keystroke after the layout changed, so a switch
  never goes unnoticed.
- **Flag at cursor** — briefly shows the layout flag next to the text caret after a switch. It
  works wherever apps expose the caret position via Accessibility; a few editors that draw
  their own text (e.g. the VS Code editor area) don't.

## Converting by hand: the trigger key

Typed a word in the wrong layout? Tap the **trigger key** — by itself, without any other key —
and Switcher3way converts the **last word** you typed and switches the layout. If you select
text first, the selection is converted instead.

Tap the trigger **again without typing anything in between** to step through the other layouts:
each extra tap retypes the word in the next installed layout and switches to it, and one more tap
past the last one brings back your original text and layout. With two layouts this is just the
familiar "tap again to undo"; with three or more it lets you reach any layout by tapping.

The trigger is configurable in **Settings → General → Trigger**:

- **Convert with** — Option ⌥ (default), Command ⌘, Control ⌃, Shift ⇧, or a two-key combo
  (⌘⇧, ⌃⇧, ⌘⌥, ⌃⌥) in the style of Windows' Alt+Shift.
- **Right key only** — react only to the right-hand modifier key.
- **Require double tap** — conversion fires on a quick double tap instead of a single tap.
  Useful when the chosen key is one you often tap alone by accident (e.g. Shift).

The manual trigger is fully N-way: it converts to the best-matching layout, and because it's an
explicit request it acts even on words that Auto-fix would leave alone (for example a word that's
valid in more than one language) — just tap again to move to the next candidate if the first
guess wasn't what you wanted. There is no layout pair to configure.

**When two layouts spell a word the same way.** Ukrainian and Russian share most letters, so a word
with no і/ї/є or ы/э/ъ looks identical in both. You get one cycle step for it, not two — an extra
tap that changed nothing visible would look like the app was broken. The layout that step switches
to is the one the dictionary points at (`хорошо` → Russian), and for a word that exists in both
languages it follows **Language for ambiguous words** in Settings → Auto-fix, the same preference
Auto-fix uses. Set that to *Do not convert* and the trigger simply takes the next layout in order.

**After an Auto-fix, the trigger keeps cycling.** Auto-fix picks one layout; tapping the trigger —
with no typing in between — walks through the *other* installed layouts for the same word, and one
more tap brings back exactly what you typed and the layout you were in. Type `dblyj`, let Auto-fix
make it `видно` in Ukrainian, then tap: Russian, then back to `dblyj`. So undoing an Auto-fix takes
one tap when there is only one other candidate, and one tap per remaining layout otherwise.

**Learning from undo:** if Auto-fix converted a word and you immediately undo it with the
trigger, Switcher3way offers to add that word to the **Never convert** list so it won't be
touched again. The offer arrives as a notification with a **Add to exceptions** button — it
never interrupts your typing, and ignoring it simply leaves the lists unchanged.

**Password fields:** the trigger does nothing in a password field. That is deliberate — an
explicit request still isn't a reason to read or rewrite a credential. See *Privacy* below for
how a password field is recognised.

**Seeing what changed:** when a conversion happens, a small badge appears next to the cursor
showing what you typed, struck through, and what replaced it — plus the trigger key, as a
reminder of how to undo it. Turn it off with **Settings → General → Show what was corrected**.
If an app doesn't tell macOS where its cursor is, the badge appears near the window instead.

**When there's nothing to convert:** the trigger always answers. If it can't do anything it tells
you why, at the cursor and as a notification, rather than appearing dead. The usual reason is that
only one keyboard layout is installed — Switcher3way converts *between* the layouts your system
has, so with a single one there is nothing to convert between; add Ukrainian or Russian and try
again. You'll also see it when nothing has been typed or selected yet, when the text is already
right for the current layout, and when a selection is longer than 200 characters.

## Auto-fix: converting as you type

**Off by default.** Enable it in **Settings → Auto-fix** or via the menu's quick toggle.

When enabled, every finished word (you typed a space) is run through the detection described
above and converted automatically when there is an unambiguous winner. Auto-fix additionally
holds back when:

- the frontmost app is in the **Apps** exception list (terminals, IDEs, password managers…);
- the word is in **Never convert**;
- the focused field is a **password field** (see *Privacy* below);
- you moved the cursor, clicked, or switched apps mid-word — converting then could damage the
  wrong text;
- the word looks like code, is ALL-CAPS, or is too short.

Words in **Always convert** are converted even if the dictionary doesn't know them.

**Ambiguous words and phrases.** A word valid in both Ukrainian and Russian converts to the
*language for ambiguous words* (default: Ukrainian). Auto-fix then remembers the phrase you're
typing (until Enter, a click, an arrow key, or an app switch). If a later word is valid in only
one language, the phrase's ambiguous words are re-converted to that language together with it —
one replacement, one trigger-tap undo. Phrases that mix clearly-Ukrainian and clearly-Russian
words are never touched retroactively.

## Exceptions

**Settings → Auto-fix → Exceptions** manages all three lists in one place. Use the segmented
filter to switch between them (counts shown live), the search field to find entries, and the
**+ Add** button to add an app (file picker) or a word (text prompt). Select an entry and press
**−** to remove it.

- **Apps** — applications where Auto-fix never runs. Ships with sensible defaults (terminals,
  IDEs, password managers). Password managers are marked **🔒 always off** and cannot be
  removed. Entries ending in `*` match a vendor prefix (e.g. all JetBrains apps).
- **Never convert** — words Auto-fix must never touch: nicknames, logins, brand names. The
  undo-learning notification adds words here.
- **Always convert** — words to convert even though no dictionary contains them.

The exception lists apply to **Auto-fix**; the manual trigger always obeys you.

## Settings reference

Open with **⌘,** from the menu. Four tabs:

### General

- **Status card** — master on/off switch for the whole app (trigger + Auto-fix).
- **Trigger** — the trigger key, right-key-only, double-tap (see above). Both the trigger and
  Auto-fix are N-way over all installed layouts; there is no layout pair to pick.
- **Show what was corrected** — the badge next to the cursor after a conversion (on by default).
- **System** — Launch at login, Remember layout per app (restores each app's last layout when
  you switch back to it), Interface language (16 languages; "System default" follows macOS).

### Auto-fix

The automatic-conversion master switch, the **Language for ambiguous words** popup
(Ukrainian / Russian / Do not convert — see *Auto-fix* above), and the exception lists.

### Advanced

- **Show layout flag at the cursor** (beta) — briefly shows the layout flag next to the text
  caret after a switch (the same *Flag at cursor* feature described above).
- **Remote Desktop mode** (beta) — for Apple Screen Sharing: run Switcher3way on the remote Mac
  too and enable this on both.
- **Debug logging** — off by default; when enabled the app writes
  `~/Library/Logs/Switcher3w/switcher3w.log` (rotated at 5 MB). **Show Log File** reveals it in
  Finder. Useful for bug reports. It records decisions, including the words being decided about —
  see *Privacy* for exactly what does and does not reach it.

### About

App name and version.

## Pausing the app

**Menu → Pause Switcher3way ▸** offers **30 minutes**, **1 hour**, or **until restart**.
While paused, nothing converts and the status icon shows **⏸**. Timed pauses resume
automatically — even if the app is relaunched in between; "until restart" ends when the app is
restarted. Select **Resume** to end any pause immediately.

## Updates

Switcher3way checks its own [releases page](https://github.com/WhisKeySwitch/switcher3way-releases/releases)
shortly after launch and once a day, and offers new versions in a dialog. **Install and
Relaunch** downloads the update, verifies it (checksum and code-signing identity), replaces
the app, and relaunches — your permissions are kept. **Later** asks again on the next check;
**Skip This Version** stays quiet about that version until a newer one appears. Turn the
automatic check off in **Settings → General → Check for updates automatically**; you can
always check manually via **menu → Check for Updates…**. Update checks talk only to GitHub
and send nothing about you or your typing.

## Privacy

Detection and conversion happen **entirely locally on your Mac** — no telemetry, no
dictionaries downloaded (it uses the macOS system dictionaries). The only network access is
the **optional update check** (see above): a request to GitHub for the latest release
version, which you can switch off in Settings → General. Keystrokes are held only in a short
in-memory buffer for the current word and are never written to disk.

**Password fields.** Neither Auto-fix, nor the trigger, nor the badge does anything while a
password field has focus. A field counts as one when *any* of these is true:

- macOS signals **secure input** — the classic case, and until recently the only check;
- the focused control is a **secure text field** as macOS describes it — what a masked
  `type="password"` box in a browser publishes;
- the focused text field is **labelled** as a password (in any of a dozen languages, matched
  against whatever the page or app calls it) even when it is *not* masked.

That last one matters: any login form with a "show password" toggle turns its box into ordinary
text while revealed, and some sites mask in their own code and never use a real password field.
Neither sets the secure-input flag. The check errs on the side of doing nothing — a field
labelled "password" is left alone even if it isn't one.

**The debug log.** Opt-in, and off unless you switch it on. It never records which keys you
pressed — only that a keystroke was buffered and how many are in the buffer. It *does* record
the word being decided about, on the line where a conversion is decided; that line cannot be
reached for a password field, because the check above runs first. If you have had logging on
and want the history gone, delete `~/Library/Logs/Switcher3w/`.

**Notifications.** Switcher3way notifies you in exactly two cases: a rewrite it could not apply,
and the offer to remember a word after you undo a conversion. It never notifies on success. If
you decline notification permission, both simply go to the log and nothing else changes.

## Troubleshooting & FAQ

**Nothing converts at all.**
Check permissions first: if the menu shows **Check Permissions…**, a grant is missing — click
it and follow the checklist. Verify the app isn't paused (⏸ in the menu bar) and the status
card in Settings → General says *On*.

**A specific word never auto-converts.**
Most likely it's absent from the macOS dictionary of the target language, or the *language for
ambiguous words* is set to *Do not convert*. Add it to **Always convert**, or just use the
trigger — manual conversion doesn't require dictionary confidence.

**Auto-fix converted something it shouldn't have.**
Tap the trigger to undo — you'll be offered to add the word to **Never convert**. If it happens
in one particular app, add that app to the **Apps** exception list.

**The trigger fires when I don't want it to.**
Enable **Require double tap**, or **Right key only**, or move the trigger to a two-key combo.

**Permissions reset after I rebuilt the app from source.**
Rebuilds must be signed with the same stable certificate — see `signing/README.md` in the
repository. Ad-hoc-signed builds lose TCC grants on every rebuild.

**Layout names show in the wrong language.**
Names follow the app's interface language. If you force an interface language different from
the macOS system language, language-neutral names (e.g. "Russian", "Terminal") are used by
design.

**Where do I report a bug?**
Enable **Debug logging** (Settings → Advanced), reproduce the issue, and attach
`~/Library/Logs/Switcher3w/switcher3w.log` — it contains decision traces (`auto: …` lines) but
not the text you typed.

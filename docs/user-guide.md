# Switcher3way — User Guide

*Also available in: [Українська](user-guide.uk.md) · [Русский](user-guide.ru.md)*

Switcher3way is a macOS menu-bar utility that notices when you've typed a word in the wrong
keyboard layout and fixes it — retyping the word in the layout you meant and switching the
keyboard for you. It works across **all** your installed layouts (e.g. English, Ukrainian,
Russian), not just a pair.

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

This is deliberately **precision-first**. If a word is valid in more than one language (`там`
exists in both Ukrainian and Russian), or looks like code, or is ALL-CAPS, or is very short,
Switcher3way leaves it alone rather than guess. A missed fix costs you one trigger tap; a wrong
fix costs you trust.

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

Tap the trigger **again without typing anything in between** to undo (convert back).

The trigger is configurable in **Settings → General → Trigger**:

- **Convert with** — Option ⌥ (default), Command ⌘, Control ⌃, Shift ⇧, or a two-key combo
  (⌘⇧, ⌃⇧, ⌘⌥, ⌃⌥) in the style of Windows' Alt+Shift.
- **Right key only** — react only to the right-hand modifier key.
- **Require double tap** — conversion fires on a quick double tap instead of a single tap.
  Useful when the chosen key is one you often tap alone by accident (e.g. Shift).

If the word is ambiguous for N-way detection, the manual trigger falls back to toggling between
your **manual pair** — the two layouts chosen in Settings → General → Manual pair.

**Learning from undo:** if Auto-fix converted a word and you immediately undo it with the
trigger, Switcher3way offers to add that word to the **Never convert** list so it won't be
touched again.

## Auto-fix: converting as you type

**Off by default.** Enable it in **Settings → Auto-fix** or via the menu's quick toggle.

When enabled, every finished word (you typed a space) is run through the detection described
above and converted automatically when there is an unambiguous winner. Auto-fix additionally
holds back when:

- the frontmost app is in the **Apps** exception list (terminals, IDEs, password managers…);
- the word is in **Never convert**;
- macOS reports **secure input** (password fields);
- you moved the cursor, clicked, or switched apps mid-word — converting then could damage the
  wrong text;
- the word looks like code, is ALL-CAPS, or is too short.

Words in **Always convert** are converted even if the dictionary doesn't know them.

## Exceptions

**Settings → Auto-fix → Exceptions** manages all three lists in one place. Use the segmented
filter to switch between them (counts shown live), the search field to find entries, and the
**+ Add** button to add an app (file picker) or a word (text prompt). Select an entry and press
**−** to remove it.

- **Apps** — applications where Auto-fix never runs. Ships with sensible defaults (terminals,
  IDEs, password managers). Password managers are marked **🔒 always off** and cannot be
  removed. Entries ending in `*` match a vendor prefix (e.g. all JetBrains apps).
- **Never convert** — words Auto-fix must never touch: nicknames, logins, brand names. The
  undo-learning prompt adds words here.
- **Always convert** — words to convert even though no dictionary contains them.

The exception lists apply to **Auto-fix**; the manual trigger always obeys you.

## Settings reference

Open with **⌘,** from the menu. Four tabs:

### General

- **Status card** — master on/off switch for the whole app (trigger + Auto-fix).
- **Trigger** — the trigger key, right-key-only, double-tap (see above).
- **Manual pair** — the two layouts the manual trigger toggles between when N-way detection is
  ambiguous. *This is not a limitation of Auto-fix* — automatic detection always covers all
  installed layouts; there is intentionally no "third layout" picker.
- **System** — Launch at login, Remember layout per app (restores each app's last layout when
  you switch back to it), Interface language (16 languages; "System default" follows macOS).

### Auto-fix

The automatic-conversion master switch, the caret-flag toggle, and the exception lists.

### Advanced

- **Debug logging** — off by default; when enabled the app writes
  `~/Library/Logs/Switcher3w/switcher3w.log` (rotated at 5 MB). **Show Log File** reveals it in
  Finder. Useful for bug reports.

### About

App name and version.

## Pausing the app

**Menu → Pause Switcher3way ▸** offers **30 minutes**, **1 hour**, or **until restart**.
While paused, nothing converts and the status icon shows **⏸**. Timed pauses resume
automatically — even if the app is relaunched in between; "until restart" ends when the app is
restarted. Select **Resume** to end any pause immediately.

## Privacy

Everything happens **locally on your Mac**. Switcher3way makes **no network connections at
all** — no update checks, no telemetry, no dictionaries downloaded (it uses the macOS system
dictionaries). Keystrokes are held only in a short in-memory buffer for the current word, are
never written to disk, and auto-fix is suppressed entirely while macOS signals secure input
(password fields). The debug log is opt-in and contains decision traces, not your text.

## Troubleshooting & FAQ

**Nothing converts at all.**
Check permissions first: if the menu shows **Check Permissions…**, a grant is missing — click
it and follow the checklist. Verify the app isn't paused (⏸ in the menu bar) and the status
card in Settings → General says *On*.

**A specific word never auto-converts.**
Most likely it's ambiguous (valid in two languages) or absent from the macOS dictionary of the
target language. Add it to **Always convert**, or just use the trigger — manual conversion
doesn't require dictionary confidence.

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

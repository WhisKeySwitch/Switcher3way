# Proposal: add-in-app-help

## Why

The user manual now exists (`docs/user-guide.md` + uk/ru translations) but only in the repository — a user of the installed app has no way to reach it. The menu has no Help entry, and the app publishes no releases or website to link out to, so help must ship **inside** the app and work offline.

## What Changes

- **Help menu item** — a "Help" entry in the menu-bar menu (after Settings…, standard ⌘? key equivalent) opening an in-app help window.
- **In-app help window** — a native window rendering the full user guide, in the language matching the app's interface language (uk/ru guides where they exist, English fallback for all other interface languages), with working in-page navigation and a language switcher (the guides already cross-link each other).
- **Keep-help-in-the-app pipeline** (the sync story): `docs/user-guide*.md` stay the **single source of truth**. `build_app.sh` converts them to styled HTML on every build (small committed converter script, no external dependencies) and bundles the result into `Switcher3way.app/Contents/Resources/help/`. Help can never drift from the repo docs because it is *generated from them* at build time — editing the manual is the only way to change in-app help, and a missing guide fails the build.
- New localized string for the menu item (16 languages).

## Capabilities

### New Capabilities

- `in-app-help`: the bundled, offline user guide — build-time generation from the repo manuals, language selection, and the help window that renders it.

### Modified Capabilities

- `menu-bar-ui-and-status-icon`: the menu gains a Help item that opens the help window.

## Impact

- **Code**: new `HelpWindowController.swift` (WKWebView-based window); `AppDelegate.swift` (menu item + action); `Localization.swift` (menu.help ×16).
- **Build**: new `scripts/md2html.py` converter (committed); `build_app.sh` gains a help-generation step; app links WebKit.
- **Docs**: CLAUDE.md architecture map + build notes; the user guides gain no new duty beyond "they are also the in-app help".
- **No impact**: detection/conversion, settings, signing (bundle resources don't affect the designated requirement).

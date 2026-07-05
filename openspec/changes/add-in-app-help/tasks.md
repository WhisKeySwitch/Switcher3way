# Tasks: add-in-app-help

## 1. Help generation pipeline

- [x] 1.1 Write `scripts/md2html.py` (stdlib-only): h1–h3, bold/italic/inline-code, links, lists, tables, blockquotes, code fences; HTML template with embedded CSS (system fonts, dark-mode via `prefers-color-scheme`); rewrites guide cross-links `.md` → `.html`; renames `user-guide.md` → `user-guide.en.html`; exits non-zero on missing source or unknown construct
- [x] 1.2 `build_app.sh`: generate `Contents/Resources/help/user-guide.{en,uk,ru}.html` from `docs/` before the codesign step; fail the build if generation fails

## 2. Help window

- [x] 2.1 Add WebKit to `Package.swift` linked frameworks; create `HelpWindowController.swift`: resizable 720×820 reusable window, WKWebView loading the bundled HTML with read access to `help/`, navigation delegate (http/https → default browser, file URLs inside help/ → in-window)
- [x] 2.2 Language resolution: `L10n.effectiveLanguage` → uk/ru guide where it exists, else English; re-resolved on every `show()`

## 3. Menu integration

- [x] 3.1 Add `menu.help` L10n key (16 languages) and accessor
- [x] 3.2 `rebuildMenu`: Help item after Settings… with ⌘? key equivalent, action opens the help window

## 4. Docs & verification

- [x] 4.1 CLAUDE.md: architecture map entry for HelpWindowController + build-pipeline note ("manuals are also the in-app help — build fails if a guide is missing"); user guides: mention Help menu item in the menu-bar section (all three languages)
- [x] 4.2 Build, install, relaunch; verify: Help opens from menu, correct language (en with English UI; force uk/ru and recheck), anchors and language cross-links work, external link opens in browser, all three guides render correctly (headings/tables/lists)

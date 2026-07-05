# Design: add-in-app-help

## Context

The app is a menu-bar utility with no releases, no website, and (since the July 2026 cleanup) zero network access — help must be bundled and offline. The manuals are Markdown (`docs/user-guide.md`, `.uk.md`, `.ru.md`), heading- and table-heavy, cross-linked to each other. `build_app.sh` already assembles the bundle and uses `/usr/bin/python3` for version stamping. `L10n.effectiveLanguage` (added in fix-display-language-and-about) resolves the interface language.

## Goals / Non-Goals

**Goals:**
- One source of truth: the repo manuals *are* the in-app help; no second copy to maintain.
- Faithful rendering of the manuals (headings, tables, anchors, cross-links), theme-aware (light/dark).
- Zero new external dependencies; build stays self-contained.

**Non-Goals:**
- No Apple Help Book (registration/`hiutil`/caching machinery is disproportionate for a menu-bar app and notoriously stale-cache-prone).
- No translation of the guide into the other 13 interface languages — those fall back to English by design.
- No in-app search (the guide is one page; ⌘F in WKWebView… is not wired; acceptable for v1).

## Decisions

### D1 — Ship pre-rendered HTML, convert at build time
Markdown → HTML conversion happens in `build_app.sh`, not at runtime. Runtime Markdown options are poor: `AttributedString(markdown:)` ignores headings and tables — the guide would render as soup. A committed `scripts/md2html.py` (Python 3 stdlib only, ~100 lines) handles the manuals' controlled Markdown subset: h1–h3, bold/italic/inline-code, links, ordered/unordered lists, tables, blockquotes, code fences. It wraps output in a fixed HTML template with embedded CSS (system font stack, `prefers-color-scheme` dark support, readable measure). The converter **exits non-zero** if a source file is missing or contains constructs it can't handle — the build fails loudly instead of shipping broken help.

Alternatives considered: WKWebView + a JS Markdown renderer (ships a JS library — dependency); NSTextView + AttributedString (unfaithful rendering); Apple Help Book (Non-Goal).

### D2 — Render in WKWebView
New `HelpWindowController.swift`: a resizable 720×820 window holding a `WKWebView`, loading `Resources/help/user-guide.<lang>.html` via `loadFileURL(_:allowingReadAccessTo:)` (read access to the `help/` directory so the language cross-links work). A navigation delegate opens `http(s)` links in the default browser and allows only file-URLs inside `help/` in-window. The window is created once and reused; each `show()` re-resolves the language file, so switching the interface language and reopening Help shows the right guide. WebKit is added to `Package.swift` linked frameworks.

### D3 — Language selection mirrors the guides that exist
`helpFileName(for: L10n.effectiveLanguage)`: `uk` → `user-guide.uk.html`, `ru` → `user-guide.ru.html`, everything else → `user-guide.en.html`. The converter renames `user-guide.md` → `user-guide.en.html` so the mapping is uniform, and rewrites the `.md` cross-links between guides to the `.html` names.

### D4 — Menu placement
Help sits directly after Settings… with key equivalent `?` + command (renders as ⌘?), matching macOS convention. Label via new `menu.help` L10n key (16 languages — one word everywhere).

### D5 — The keep-in-sync contract
Documented in CLAUDE.md: *the manuals are also the in-app help*. Any UI/behavior change updates `docs/user-guide*.md`; the next build bundles it automatically. There is deliberately no separate help content to edit — the generation step is the enforcement mechanism (specs: "Source guide missing → build fails").

## Risks / Trade-offs

- [Hand-rolled Markdown converter mis-renders an edge case] → the subset is small and the input is controlled (three files we author); converter fails on unknown constructs instead of guessing; visual check of all three guides is an explicit task.
- [WKWebView adds WebKit linkage] → framework is on every macOS install; app stays dependency-free. Binary size impact ≈ 0 (dynamic linking).
- [`codesign --deep` must cover added resources] → resources are content-hashed by the signature automatically; no script change beyond generation order (generate *before* signing — the step is inserted before the codesign step in build_app.sh).
- [Guide renders differently in the window vs GitHub] → acceptable; the HTML template targets readability, not GitHub parity.

## Open Questions

- None blocking.

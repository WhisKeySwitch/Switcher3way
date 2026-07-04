# Design: fix-display-language-and-about

## Context

macOS localizes framework-provided strings — `kTISPropertyLocalizedName` (input sources), `FileManager.displayName` (app bundles), AppKit chrome like window titles — against the **app bundle's declared localizations**, not the user's system language directly. **Root cause found during implementation:** the fork inherited `CFBundleDevelopmentRegion = ru` from upstream and bundles no `.lproj` resources, so the app's only declared localization is Russian and every framework string resolves to Russian ("Без названия", "Русская", "Терминал") even on an English-language system (this user's system is `en-US`). The app's own `L10n` strings are unaffected (compiled-in, driven by `Locale.preferredLanguages`), which is why the interface was English while names were Russian. Affected call sites: `LayoutSwitcher.sourceName`/`currentLayoutName` (menu header via `AppDelegate`, popups via `SettingsWindowController.populateLayoutPopup`) and `ExceptionsPane.displayText`.

## Goals / Non-Goals

**Goals:**
- One rule everywhere a layout or app name is rendered: match the app's effective interface language.
- Keep the best-quality (system-localized) names whenever they're consistent anyway.

**Non-Goals:**
- No per-language translation of layout/app names by the app itself (we don't ship name catalogs); the fallback is language-neutral, not translated.
- No change to what is *stored* (bundle ids, input-source IDs stay the keys).

## Decisions

### D0 — Fix the bundle's localization declaration (the actual root cause)
Set `CFBundleDevelopmentRegion` to `en` and add `CFBundleAllowMixedLocalizations = YES` in Info.plist. With mixed localizations allowed, Foundation/AppKit fetch their strings in the **user's** preferred language instead of being pinned to the app's development region — window titles, `FileManager.displayName`, and TIS layout names all start following the system language. This alone fixes the reported case (English system, Russian names). D1–D3 remain as the second layer for the genuinely mixed configuration (app UI forced to a language different from the system).

### D1 — "Consistent" = app effective language equals system language prefix
Expose `L10n.effectiveLanguage` (the resolved `currentLang`, already computed by `detectLanguage()`) and compare with `Locale.preferredLanguages.first`'s two-letter prefix. Equal → use system-localized names; different → neutral fallback. Rationale: when the user runs "system default" (the common case) nothing changes; the fallback only kicks in for the mixed-language configuration that looks broken.

### D2 — Neutral layout names from the input-source ID
`LayoutSwitcher.displayName(_ source:)` returns `sourceName(source)` (TIS localized) in the consistent case, else the last dot-component of the input-source ID with light cleanup (hyphens → spaces, e.g. `Ukrainian-PC` → "Ukrainian PC", `US` stays "US"). Apple's keylayout IDs are English-ish by construction. `currentLayoutName()` routes through the same helper. Alternative considered: reading the layout's name from its `.keylayout` bundle for a specific locale — no public API, rejected.

### D3 — Neutral app names from the bundle's on-disk name
In `ExceptionsPane`, in the inconsistent case use the app bundle URL's `lastPathComponent` minus `.app` instead of `FileManager.displayName`. On-disk names of system and third-party apps are effectively English. The wildcard `*`-suffix vendor entries keep their current rendering. The info cache stays keyed by bundle id — the language can only change via the Settings language popup, which rebuilds the whole window (and its pane) anyway.

### D4 — About centering
The About tab builder wraps its labels in a centered column: the tab root's `NSStackView` alignment for this tab becomes `.centerX` (add an `alignment:` parameter to `makeTabRoot`, defaulting to `.leading`), labels get `alignment = .center`.

### D5 — Trigger config flip is operational
`triggerDoubleTap = true` is the user's preference change, applied via `defaults write com.switcher3way.app com.ruswitcher.triggerDoubleTap -bool true` + app restart (the trigger config is read when the event tap is (re)created). No code change; recorded as a task so it isn't lost.

## Risks / Trade-offs

- [ID-derived names are less pretty ("RussianWin")] → acceptable: they only appear in the deliberately mixed-language configuration, and they're recognizable; cleanup keeps the common cases ("US", "Russian", "Ukrainian PC") tidy.
- [`Locale.preferredLanguages` reflects the app's own launch environment, not live system changes] → same behavior as `L10n.detectLanguage()` already has; a system-language change requires app relaunch either way.

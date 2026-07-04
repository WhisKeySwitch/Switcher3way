# Tasks: fix-display-language-and-about

## 1. Interface-language-consistent names

- [x] 1.1 Expose `L10n.effectiveLanguage` and add `LayoutSwitcher.namesFollowSystem` check (effective app language == system language prefix) plus `displayName(_:)` / language-neutral ID fallback with hyphen cleanup; route `currentLayoutName()` through it
- [x] 1.2 Use `LayoutSwitcher.displayName` in the menu status header (AppDelegate) and the manual-pair popups (SettingsWindowController)
- [x] 1.3 `ExceptionsPane.displayText`: in the mixed-language case use the bundle URL's on-disk name (lastPathComponent minus ".app") instead of `FileManager.displayName`
- [x] 1.4 Info.plist: `CFBundleDevelopmentRegion` ru → en, add `CFBundleAllowMixedLocalizations = YES` — the app was pinned to its Russian development region, which is why framework strings (window titles, display names, TIS names) came out Russian on an English system

## 2. About tab centering

- [x] 2.1 Add `alignment:` parameter to `makeTabRoot` (default `.leading`); About tab uses `.centerX` with centered labels

## 3. Config + verification

- [x] 3.1 Flip the user's trigger preference to double-tap Shift (`defaults write com.switcher3way.app com.ruswitcher.triggerDoubleTap -bool true`) and restart the app
- [x] 3.2 Build, install, relaunch; verify via debug log; user visually confirms English names in header/popups/exceptions and centered About

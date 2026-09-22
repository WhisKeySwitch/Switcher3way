## Why

Switcher3way has no distribution. Across every macOS release ever published, on both repositories, the DMG has been downloaded roughly 45 times in total — 1.5.2, the most recent before this month, got 8. The app is finished and nobody can find it. The Mac App Store is the one channel that supplies discovery and payment together, and it is the only way to sell this app at all: StoreKit in-app purchase exists solely for App Store apps, so every alternative means building and maintaining a licensing system, a storefront integration and tax compliance by hand.

The App Store was believed to be closed to this app because the sandbox forbids what it does. That belief was tested on 2026-09-15 and 2026-09-20 and is wrong. A sandboxed build of this exact source, granted Accessibility and Input Monitoring, converted `ghbdtn` to `привет` and switched the layout end to end. Caramba Switcher — a direct competitor doing the same job — has shipped on the App Store since 2021, fully sandboxed, with no exception entitlements.

## What Changes

- **A second build flavour: a sandboxed App Store variant**, produced from the same sources as the direct build, selected by a build flag. This mirrors the Windows port's existing MSI/MSIX split and its `PackageInfo.IsPackaged` branching.
- **The password-field guard becomes variant-dependent.** `AXUIElement` inspection of other applications does not work under the sandbox (`err=-25204` sandboxed against `err=0 ELEMENT` unsandboxed, same binary, same focused element, same instant). The Store variant's guard is built from `IsSecureEventInputEnabled()` plus the frontmost-application exception list, both of which were measured to survive.
- **The Store variant ships without the updater.** Apple forbids App Store apps from updating themselves; `UpdateChecker` and `UpdateInstaller` compile out behind the same flag.
- **Purchase via StoreKit**: a free download with a two-week introductory trial on an auto-renewable subscription, plus a non-consumable lifetime unlock.
- **The direct channel survives, unchanged and free.** It keeps the full Accessibility-based guard, the Developer ID signature, the notarized DMG and the existing updater, and every installed copy keeps receiving free updates indefinitely. No licence gate is added to it — see `design.md` for why one could not be built honestly anyway.
- **Distinct bundle identifiers** for the two variants, so both can be installed at once and compared — necessary precisely because their password guards differ.

## Capabilities

### New Capabilities
- `app-store-distribution`: the sandboxed Store variant — what the sandbox permits and forbids, which capabilities degrade, how the flavour is built and identified, and what must be true before submission.
- `purchases-and-entitlement`: StoreKit trial, subscription and lifetime unlock; how entitlement is determined, restored on a new Mac, and what the app does when it lapses.

### Modified Capabilities
- `password-field-protection`: requirements currently assume the focused Accessibility element can be inspected. They must be restated so the guarantee is expressible in a build where it cannot, without weakening the unsandboxed build. The fail-open principle needs strengthening, not relaxing: in the Store variant a silently absent signal is the normal case rather than an error.
- `software-updates`: must state that the App Store variant performs no update check and no self-install, and that the direct variant is unchanged.
- `distribution-and-releases`: currently requires release notes and the README to tell users the app is unnotarized and needs right-click → Open. As of 1.6.2 the direct build is signed and notarized, so that requirement is already stale; this change restates the capability around two channels with different installation stories.

## Impact

- **Code**: `SecureFieldDetector` (signal set becomes variant-dependent), `AutoSwitchPolicy`, `CaretIndicator` (no caret resolution under sandbox; falls back to its existing window anchor), `TextConverter` (loses AX read-back verification), `UpdateChecker`/`UpdateInstaller` (compiled out), `main.swift`/`AppDelegate` (flavour branching), plus a new purchase layer.
- **Build**: `Package.swift` gains a compilation condition; `build_app.sh` gains a flavour argument, a sandbox entitlements file and a second bundle identifier. `create_dmg.sh` is unaffected — it serves the direct channel only.
- **Unaffected**: `Switcher3wCore` in its entirety. The resolver, typo guard, short-word lists and phrase tracking are Foundation-only and identical in both variants, so detection quality does not fork.
- **External**: an App Store Connect record, a registered bundle ID, privacy labels, and review. The Developer ID certificate and notarization pipeline built this month remain in use for the direct channel.
- **Not addressed here**: whether the direct build gains a gift licence gate, or whether Apple's promotional codes cover friends and family instead. That decision is recorded as open in `design.md`.

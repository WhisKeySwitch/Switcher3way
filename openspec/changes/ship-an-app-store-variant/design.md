## Context

See `proposal.md` — Why. The measurements that make this change possible are recorded there; what matters here is what they constrain.

The app is a single SwiftPM executable target (`Switcher3w`) plus a Foundation-only library (`Switcher3wCore`), packaged by `build_app.sh` and signed with a Developer ID identity read from `signing/developer-id.conf`. The Windows port already solves the same two-flavour problem: `-p:Packaged=true` builds the Store package, the default builds the installer, and `PackageInfo.IsPackaged` branches the updater and the startup mechanism. That pattern is proven in this project and is worth copying rather than reinventing.

Three sandbox facts shape everything below, each measured on macOS 27.0 with the same binary signed two ways:

- keystroke monitoring, `CGEventPost`, layout switching, frontmost-application identity, window titles and pasteboard reads all work;
- inspecting another application's Accessibility elements does not (`err=-25204` sandboxed, `err=0` unsandboxed, same focused element, same instant);
- the process-global secure-input flag works, and browsers set it for password inputs — 40 of 40 samples with a Chrome password field focused.

## Goals / Non-Goals

**Goals:**

- One source tree, two flavours, with detection logic that cannot fork between them.
- A password guard whose degradation in the sandboxed flavour is explicit in the code and visible in diagnostics, never inferred from an absent log line.
- Purchase handled entirely by the platform, with no licence format, no activation server and no trial clock of our own.

**Non-Goals:**

- Retiring the direct channel, or changing what it does. It keeps the full guard, its updater and its notarized DMG.
- Deciding how the direct channel is gated against people who simply download it instead of buying. See Open Questions.
- Any change to the resolver, typo guard, short-word lists or phrase tracking. Detection quality is out of scope in both directions.

## Decisions

**A compilation condition, not a second target.** Add a `SWITCHER_APPSTORE` Swift compilation condition, selected by an argument to `build_app.sh`. A second SwiftPM target would duplicate the packaging, the resource copying and the Info.plist stamping, and the two copies would drift — the class of bug this project already documents for stale build paths and mismatched version stamps. A condition keeps one build path with two outputs. The cost is that the App Store flavour is not continuously compiled unless someone builds it, which the tasks address by building both in the release check.

**Distinct bundle identifiers**, direct keeping `com.switcher3way.app`. The direct identifier already holds Accessibility and Input Monitoring grants on every installed machine; changing it would silently drop them for existing users. The Store variant takes a new identifier, which also lets both be installed at once — necessary because the entire point of the comparison is that their guards differ. The consequence is that a user moving from direct to App Store re-grants permissions and starts with default settings; sandbox containerization would force the settings half of that regardless.

**The password guard reports three states per signal, not two.** `SecureFieldDetector` currently answers positive/negative per signal. Under the sandbox the element-based signals cannot run at all, and reporting "negative" for a check that never executed is exactly the failure this project has already been bitten by — a guard that works and a guard that never ran leaving identical evidence. The verdict type gains `unavailable`, the diagnostic prints it, and the fail-open behaviour is unchanged.

**The conversion chip needs a new anchor, not the existing fallback.** An earlier draft of this
document said the chip would "fall back to its existing window anchor" under the sandbox. That was
wrong: the window anchor is itself resolved through `AXUIElementCreateApplication` and
`kAXFocusedWindowAttribute`, so it fails for exactly the same reason caret resolution does, and the
sandboxed build has no position to draw at. `CGWindowListCopyWindowInfo` returns window bounds and
was measured working under the sandbox, so it replaces the AX path as the fallback. Found by
verifying rather than reasoning — the chip simply never appeared.

**Application-level suppression compensates for element-level loss.** `NSWorkspace.frontmostApplication` survives the sandbox, so `AutoSwitchPolicy`'s denied-application list and its always-off password managers keep working. That is the fallback, and it is weaker: it protects whole applications rather than individual fields. The spec requires disclosing this rather than presenting the variants as equivalent.

**The direct channel stays free, for everyone, indefinitely.** Every installed copy keeps
receiving free updates — decided outright, not inferred. The consequence is larger than the
promise: the updater fetches its DMG from a public GitHub release, so the build that serves
existing users is the same build anyone can download fresh. Nothing distinguishes an existing
install from a new one at download time, and the signals that might approximate it — a first-run
marker, existing settings, an existing permission grant — are all local state a new user can
produce and an honest user can lose by reinstalling. A gate built on them would lock out the
people it was meant to protect and stop nobody else.

So there is no licence gate on the direct channel, and the App Store version cannot sell on
exclusivity: the same software is free a click away. What it sells is discovery, a one-click
install with no Gatekeeper story, purchases and refunds handled by Apple, and updates that arrive
without this project's own updater. That is a real proposition, but it is a different one from
"pay to use this", and the pricing and listing should be written knowing it.

**StoreKit 2**, with one auto-renewable subscription carrying an introductory free trial and one non-consumable unlock. Entitlement is read from the platform's current entitlements rather than cached locally, so reinstalls and second Macs resolve themselves. StoreKit 1 is rejected: it would mean manual receipt validation, which is more code and more ways to lock out a paying user.

**The updater is compiled out, not disabled.** `#if !SWITCHER_APPSTORE` around `UpdateChecker`, `UpdateInstaller`, their menu items and their settings row. A runtime flag would leave the code, the network calls and the preference present in the shipped binary, which is both a review risk and a thing a future edit could re-enable by accident.

**Entitlement resolves in the user's favour when unknown.** A paying user locked out by a network failure is a worse outcome than an unpaying user getting a free session. The app continues for the session, logs the reason, and re-checks.

## Risks / Trade-offs

- **Review rejects an app that reads every keystroke** → Caramba Switcher has shipped exactly this, sandboxed and without exception entitlements, since 2021. Mitigate further with accurate privacy labels (no data collected, nothing leaves the machine) and a purpose string that says plainly why the app needs what it needs.
- **The sandboxed guard misses a credential that the direct build would have caught** → The measured gap is narrow: browsers set the secure-input flag for real password inputs. What remains exposed is non-standard JS-masked fields and revealed "show password" boxes. Mitigated by the application-level list and by disclosure; not eliminated. This is the trade-off being accepted, and it should be stated in the listing rather than buried.
- **The two variants drift** → Detection lives in `Switcher3wCore`, which neither flavour conditionalises. The risk is in the shell: policy, feedback and packaging. Mitigated by building both flavours in the release check.
- **Something else in the shell breaks under the sandbox and is not noticed** → Notifications, launch-at-login and in-app help have not been exercised in a sandboxed build. Tasks include verifying each, in the flavour that ships.
- **A free direct download undercuts paid Store sales** → Accepted deliberately, not mitigated. The direct channel stays free so existing users keep their updates (see Decisions), which means anyone willing to find the releases page pays nothing. The Store version competes on discovery and convenience instead. If that proves too thin to sell against, the answer is to reconsider whether to charge at all — not to quietly break the promise to existing users.

## Migration Plan

Additive. The direct channel is untouched at every step, so there is nothing to roll back for existing users: no shipped behaviour changes until the App Store variant is submitted, and the App Store variant has no users until it is approved.

Order: build flavour first, then the guard restructuring (which improves the direct build's diagnostics too, and is worth shipping there regardless), then updater exclusion, then purchase, then submission. If the change is abandoned after any of the first three steps, what has landed is still correct for the direct build.

Rollback after release is removal from sale, which does not affect installed copies or the direct channel.

## Open Questions

- The final trial length and the two prices. The specs deliberately say "time-limited" rather than naming a number.
- Whether a revealed "show password" field keeps the secure-input flag set. The 40-sample measurement did not distinguish this, and it sizes the residual gap. Worth measuring before the listing text is written, but it does not change the architecture.

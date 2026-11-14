# Proposal

## Why

The App Store build is the channel meant to give the app discovery, and discovery on the store runs
on ratings. A listing with no ratings converts poorly, and satisfied users of a utility that works
silently rarely think to leave one: when Switcher3Way is doing its job, nothing on screen reminds
anyone it exists. So the app should ask, once it has earned it, in the one way Apple allows.

Apple allows exactly one mechanism. Guideline 5.6.1 requires apps to use the system review API and
disallows custom review prompts. That API decides for itself whether to show anything, shows at most
three prompts per app in 365 days, and never reports back whether it did. What the app controls is
*when* it asks — and for this app that is the hard part, because it is a menu-bar utility that
lives behind whatever the user is typing into. A prompt that appears mid-sentence would steal focus
from the one activity the app exists to protect.

## What Changes

- **The App Store build asks for a rating through the system review API**, and only there. The
  direct build is unchanged: it is not on the store and cannot be rated there.
- **It asks only after the app has proved useful:** a threshold of automatic conversions the user
  kept (not undone within the existing undo window), a minimum number of days since first launch, and
  an entitlement that still allows conversion. A user whose trial has ended is never asked.
- **It asks only while the user has the app in front by their own action** — when they open
  Settings. It never asks while they are typing, never activates the app to ask, and never asks
  from the menu, whose tracking a system sheet would break.
- **It asks at most once per app version**, and not again within 120 days of its last request,
  whatever the system's own limit would allow.
- **A "Rate Switcher3Way on the App Store…" menu item** is always present in the App Store build, so
  someone who wants to rate does not have to wait for the prompt. It opens the listing's review page.
- **Every decision is logged**, including the decision not to ask yet and why, following the rule the
  rest of the app keeps. The counters hold numbers only, never text.

## Capabilities

### New Capabilities

- `app-store-review-prompt`: when and how the App Store build asks for a rating, the always-available
  rate menu item, and what is recorded to decide it.

### Modified Capabilities

None. The existing capabilities do not change behaviour; the App Store build gains a separate one.

## Impact

- **App (`Sources/Switcher3w/`):** a review coordinator compiled into the App Store flavour only;
  hooks in `AppDelegate` at the point where an automatic conversion's undo window closes without an
  undo, and when Settings opens; a menu item; persisted counters in `SettingsManager`; strings in
  the 16 interface languages for the menu item.
- **Core (`Sources/Switcher3wCore/`):** the eligibility rule as a Foundation-only type, so it is
  unit-tested with an injected clock rather than trusted.
- **External:** the listing's numeric App Store ID, needed for the review page link. It is not in the
  repo and has to be read from App Store Connect.
- **Unaffected:** the direct build, the detection core's behaviour, purchases and entitlement.

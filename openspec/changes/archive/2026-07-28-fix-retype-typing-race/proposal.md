# Fix Retype/Typing Race

## Why

When the user keeps typing right after a word boundary, the asynchronous retype engine (synthetic backspaces + Unicode insert, ~50–150 ms) races with the live keystrokes: the backspaces erase the user's *fresh* characters instead of the mis-typed word, and the replacement text lands mid-stream. A real phrase like «Добре, що є прогрес» typed fast came out as `Lj,ht? oДобре,прес )`. This destroys user text — the exact opposite of the app's precision-first promise ("on any uncertainty, do nothing").

## What Changes

- The retype engine (`TextConverter`) aborts injection as soon as a real (non-synthetic) keystroke is detected after the conversion was scheduled — before the first backspace and between individual injection steps.
- An aborted injection restores what it already erased (re-inserts the erased tail) so the screen is never left in a half-erased state, and reports failure so the caller does not switch the layout or mark the word converted.
- The layout switch and post-conversion bookkeeping in `handleAutoConvert` move to a completion callback that only fires if injection ran to completion — the layout must not flip mid-phrase when the conversion was abandoned.
- The abort guard lives in the shared injection path, so the manual ⌥-trigger cycle gets the same protection for free (behavioral requirements of manual conversion are unchanged: an explicit trigger with no concurrent typing behaves exactly as before).

## Capabilities

### New Capabilities

_None._

### Modified Capabilities

- `automatic-conversion-on-word-boundaries`: new requirement — automatic conversion SHALL be aborted (and any partial erase undone) when the user continues typing while the conversion is being injected; the layout SHALL only switch after the text replacement completed.

## Impact

- `Sources/Switcher3w/TextConverter.swift` — abort flag + checks in `retype`/`backspace`/`insertText`, partial-erase restore, completion reporting.
- `Sources/Switcher3w/KeyboardMonitor.swift` — signal "real key arrived" to the converter (thread-safe, set from the event-tap callback).
- `Sources/Switcher3w/AppDelegate.swift` — `handleAutoConvert` defers `LayoutSwitcher.switchTo` / `markConverted` / status-icon update until injection success is known.
- No settings, UI, or user-guide changes; no new permissions. Docs untouched (behavior only becomes *more* conservative, which `docs/user-guide.md` already describes as the design intent).

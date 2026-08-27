## 1. Diagnose

- [x] 1.1 Found in a real user's log: `auto: "ьукпув" -> "merged" : Mismatch`, twice on the same word.
- [x] 1.2 Reproduced in Notepad — `erased 7`, `caret 7 -> 6, expected 7`, repaired back.
- [x] 1.3 Root cause: the replacement is injected character by character as Unicode code points, and a
      Windows edit control ignores U+000A. The boundary is part of what gets erased and re-typed, so
      the replacement is always one character short.
- [x] 1.4 Measured the obvious alternative: carrying U+000D instead of U+000A. Ignored as well —
      recorded so it is a finding rather than something to rediscover.

## 2. Fix

- [x] 2.1 Decline conversion when the boundary cannot be reproduced, logging the reason.
- [x] 2.2 Do not notify: nothing failed, the app chose not to act.
- [x] 2.3 Report rewrite failures in terms of what failed — `notify.mismatch` and `notify.partial`
      alongside `notify.protected`, in all three languages, instead of blaming elevation for
      everything.

## 3. Verify

- [x] 3.1 `ghbdsn` + Enter in Notepad: declined, one log line, no rewrite, no repair, no notification.
- [x] 3.2 `cnjkbwz` + space in the same session: converted to `столиця` : Ok — normal conversion is
      untouched.
- [x] 3.3 The Mismatch path now reports "the replacement didn't land correctly, so your original text
      was put back", observed in a real run before the fix landed.
- [x] 3.4 Every localization key referenced by the code exists in all three languages.
- [x] 3.5 178 tests green.
- [x] 3.6 Confirmed on the **shipped Store build 0.4.1**, which is the strongest form this could take
      — not a test package, the thing users have:

      ```
      auto: "ghbdsn" not converted — the word ends with Enter, whose boundary character cannot be re-typed
      auto: "cnjkbwz" -> "столиця" [uk] via Primary : Ok
      ```

      One log line and no rewrite for the Enter case, and **no notification** — which is the point:
      before this, that same keystroke produced a failed rewrite, an undo, and a message blaming
      administrator rights. A space-terminated word converts as it always did.

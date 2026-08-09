## 1. Split the veto

- [ ] 1.1 In `Sources/Switcher3wCore/SoftGates.swift`, replace `looksLikeCodeIdentifier` with two
      predicates: `hasInternalCapital` (the camelCase half) and `isMixedScript` (the Latin+Cyrillic
      half), each with a comment saying why it is or is not Caps-Lock-gated
- [ ] 1.2 In `passes`, check `isMixedScript` before the `if !capsLock` branch; leave `isAllCaps` and
      `hasInternalCapital` inside it

## 2. Tests

- [ ] 2.1 Flip `testMixedScriptIsAllowedThroughUnderCapsLock` into
      `testRejectsMixedScriptUnderCapsLock`, asserting rejection, and drop the "documents current
      behavior" comment
- [ ] 2.2 Fold the caps-off mixed-script assertion back into `testRejectsMixedScript` so both shift
      states are covered by one intent
- [ ] 2.3 Keep `testAcceptsCamelCaseShapeUnderCapsLock` and `testAcceptsAllCapsUnderCapsLock` green —
      those exemptions are deliberate and must not regress
- [ ] 2.4 `swift test` passes

## 3. Close-out

- [ ] 3.1 `bash build_app.sh` succeeds and the bundle signs with the stable identity
- [ ] 3.2 `openspec validate fix-mixed-script-capslock-gate --strict`, then archive

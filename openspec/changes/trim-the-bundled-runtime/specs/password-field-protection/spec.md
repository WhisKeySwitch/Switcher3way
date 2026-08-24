## ADDED Requirements

### Requirement: A guard that fails open SHALL be verified after any build-configuration change
Password-field detection is deliberately fail-open: every failure answers "not a password", so that a
broken detector can never stop the user typing. That choice makes the guard's failure invisible from
the outside — the application goes on converting text exactly as it does when the guard is working —
so its correctness cannot be inferred from the application appearing to run.

Any change to how the application is compiled, trimmed, linked or packaged SHALL therefore be treated
as capable of disabling the guard until demonstrated otherwise, and SHALL NOT be adopted on the
evidence of a successful build, a successful launch, or successful conversion alone.

#### Scenario: A build configuration that disables detection is not shippable
- **WHEN** a build or packaging configuration removes, or renders unusable, a mechanism the guard depends on — COM interop, reflection over accessibility interfaces, or the accessibility client itself
- **THEN** that configuration SHALL NOT be adopted, however much it improves size or speed, unless the mechanism is restored and the guard demonstrated working

#### Scenario: The guard is proven against a real password field, not inferred
- **WHEN** a build configuration change is evaluated
- **THEN** the guard SHALL be exercised against an actual focused password field in a browser — the case that depends on the accessibility path rather than on the operating system's secure-input flag — and the verdict read from its own diagnostic output

#### Scenario: Losing a detection signal is reported even when the app still works
- **WHEN** the guard loses one of its signals at runtime
- **THEN** it SHALL record that unconditionally, through the always-on diagnostic path, naming the signal and stating that the fields relying on it will no longer be detected

## ADDED Requirements

### Requirement: Carry the runtime economically
The Windows build carries its own runtime because the Store channel requires it, and that runtime is
the overwhelming majority of what users download. The build SHALL therefore include only what it
needs, insofar as that can be achieved without weakening the application.

Reducing the payload SHALL NOT be traded against correctness. Where a size reduction removes machinery
that a feature depends on — reflection, COM interop, dynamically loaded interface resources — the
feature SHALL be shown to still work before the reduction is adopted, and the reduction SHALL be
abandoned rather than shipped with the feature broken.

#### Scenario: The runtime carries no components the application never uses
- **WHEN** the application is published for distribution
- **THEN** framework components that nothing in the application references SHALL NOT be included, where the build system can establish that safely

#### Scenario: A size reduction that breaks a feature is abandoned, and the finding recorded
- **WHEN** a size reduction is measured to break any application behaviour that cannot then be restored
- **THEN** the reduction SHALL NOT be shipped, and the result SHALL be recorded so that it is a finding which can be re-tested rather than folklore to be rediscovered

#### Scenario: Size is measured as shipped, not as laid out on disk
- **WHEN** the benefit of a size reduction is assessed
- **THEN** it SHALL be measured on the compressed package the user actually downloads, because the payload's components compress at very different ratios and the on-disk figure misstates which of them are worth attention

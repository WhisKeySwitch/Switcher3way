# detection-core-testability Specification

## Purpose
TBD - created by archiving change windows-parity-macos. Update Purpose after archive.
## Requirements
### Requirement: Expose the detection core as a testable module
The platform-independent decision logic — soft gates, letter-core trimming, N-way candidate
evaluation, phrase tracking, and exception-list matching — SHALL live in a module that a test target
can import, separate from the executable target. Platform services the logic depends on (dictionary
validation, installed-layout enumeration, per-layout rendering) SHALL be reachable through
substitutable interfaces so tests can supply deterministic doubles.

#### Scenario: Test target imports the core
- **WHEN** the test target is built
- **THEN** it SHALL be able to import the detection core and call its decision entry points without launching the application or requiring Accessibility permission

#### Scenario: Deterministic dictionary in tests
- **WHEN** a test supplies its own dictionary validator and layout catalog
- **THEN** the detection core SHALL use them instead of the system spell checker and the system input sources, so results do not depend on the machine's installed layouts or languages

### Requirement: Cover the detection decisions with automated tests
The repository SHALL carry an automated test suite, runnable with the package manager's test command,
covering at minimum: the soft gates (length, all-caps, mixed-script, code-identifier, letter-core
trimming), the N-way evaluation outcomes (keep, convert, ambiguous), the ambiguity preference and
phrase-lock precedence, phrase correction and its reset boundaries, and exception-list matching for
never-convert and always-convert.

#### Scenario: Running the suite
- **WHEN** a developer runs the package test command in a clean checkout
- **THEN** the suite SHALL execute without requiring the app to be installed, signed, or granted any permission, and SHALL report pass or fail per case

#### Scenario: A detection regression
- **WHEN** a change alters an N-way outcome for a covered input
- **THEN** at least one test SHALL fail, identifying the input and the expected versus actual outcome

### Requirement: Measure dictionary validation quality against a fixture
The suite SHALL include a test that measures the dictionary validator against a checked-in fixture of
words per supported language, reporting how many known-good words validate and how many known-bad
words are rejected, so that a change in the validation path is caught as a measured quality shift
rather than an unnoticed behavior drift.

#### Scenario: Validator quality is measured
- **WHEN** the dictionary-quality test runs against the checked-in fixture
- **THEN** it SHALL report the pass rate per language and SHALL fail if the rate falls below the recorded threshold

#### Scenario: A language's dictionary is unavailable on the machine
- **WHEN** the system dictionary for a fixture language is not available in the test environment
- **THEN** the test SHALL skip that language explicitly rather than reporting a false pass


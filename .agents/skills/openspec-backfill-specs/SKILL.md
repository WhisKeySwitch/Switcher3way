---
name: openspec-backfill-specs
description: Auto-extract OpenSpec capability specs from an existing codebase. Use when the user wants to onboard OpenSpec into a brownfield project by generating spec.md files for capabilities that already exist in code.
license: MIT
compatibility: Requires openspec CLI.
metadata:
  author: project-local
  version: "1.0"
---

Automate OpenSpec onboarding for an existing project: detect the stack, fill in
`openspec/config.yaml` context, map capabilities from the codebase, and write
one validated `openspec/specs/<capability>/spec.md` per capability.

This is for **brownfield onboarding** — back-filling specs from code that
already exists. For greenfield "design before code" work, prefer
`openspec-propose`.

**Input**: No required arguments. Optional flags:
- `--scope <both|backend|frontend>` — limit extraction surface (default: auto-detect)
- `--depth <full|core|map>` — granularity (default: `full`)
    - `full`: every capability, per-requirement scenarios
    - `core`: top 3–5 capabilities only
    - `map`: a single overview doc at `openspec/CAPABILITIES.md`, no individual specs

**Steps**

1. **Preflight**

   ```bash
   openspec --version 2>&1 || echo "CLI_NOT_INSTALLED"
   ```

   If not installed, stop and instruct the user to
   `npm i -g @fission-ai/openspec`.

   Check `openspec/config.yaml` exists; if not, run `openspec init` (no tools
   flag — Codex wiring is presumed already present) before continuing.

2. **Idempotency guard**

   ```bash
   openspec list --specs
   ```

   If any specs already exist, use **AskUserQuestion** to ask:
   "Specs already exist. What should I do?" Options:
    - **Overwrite all** (backs up existing specs to `openspec/specs.bak-<YYYY-MM-DD>/` first)
    - **Skip existing capabilities** (only extract those without a folder)
    - **Abort**

   Default to "Skip existing" if the user dismisses without choosing.

3. **Detect project structure**

   Without asking the user, scan the repo:
    - Markers at root and one level deep: `*.csproj`, `*.sln`, `go.mod`,
      `Cargo.toml`, `pyproject.toml`, `package.json`, `pom.xml`, `build.gradle`.
    - Read `README.md`, root `AGENTS.md`, and any per-surface `AGENTS.md`
      (e.g. `ui/AGENTS.md`) for stack hints.
    - Identify backend root(s) and frontend root(s) when both exist.

   If `--scope` was provided, honor it. Otherwise derive from detection.

4. **Populate `openspec/config.yaml`**

   Read the current file. If `context:` is missing or empty, write a
   block summarizing:
    - Repo purpose (1 line)
    - Layout (backend dir, frontend dir, key subprojects)
    - Backend stack: language/runtime version, framework, persistence,
      messaging, auth, validation, key libraries
    - Frontend stack: language, framework, state management, package
      manager, test tooling
    - Tooling & process: CI provider, branching style, sibling services
      this project integrates with

   Add a `rules:` block with starter rules adapted to the detected stack
   (e.g. for a BE+FE repo: "note BE/FE side affected up front", "include
   EF migration task for persistence changes", "include Jest + Playwright
   test tasks for FE changes").

   **Do not overwrite a non-empty `context:`** — leave it alone.

5. **Map capabilities (Explore subagent)**

   Spawn the Explore subagent with a prompt that:
    - Lists the exact paths to inspect (BE project dirs, FE `src/` dir).
    - Asks for a structured report covering:
        1. **Capability list** — for each: kebab-case name, 1-line
           description, key endpoints/controllers, key application services or
           commands, key domain entities, notable rules/invariants, FE
           pages/routes (if applicable).
        2. **Cross-cutting concerns** (tenancy, audit, feature toggles,
           validation, error shape).
        3. **External integrations** (auth providers, message brokers,
           caches, object storage, email, metrics).
        4. **FE-specific capabilities** with no direct BE counterpart.
    - Caps the report at ~1500 words and aims for 10–25 capabilities (not 100).

   If `--depth=core`, ask for the 3–5 highest-value capabilities only.
   If `--depth=map`, write the returned map to `openspec/CAPABILITIES.md`
   and **skip step 6**.

6. **Write specs**

   For each capability (filtered by step 2's choice), write
   `openspec/specs/<kebab>/spec.md` with this exact structure:

   ```markdown
   # <Capability Title>

   ## Purpose

   <1–3 sentences. What does this capability do? Who uses it?>

   ## Requirements

   ### Requirement: <Imperative requirement name>
   The system SHALL <normative statement>.

   <Additional SHALL/MUST sentences in the same block as needed.>

   #### Scenario: <Descriptive scenario name>
   - **WHEN** <trigger>
   - **THEN** <outcome>
   ```

   **Format rules — non-negotiable, the parser is strict:**
    - `## Purpose` heading is **required**.
    - `## Requirements` heading is **required**.
    - Each requirement uses `### Requirement: <name>` (exactly 3 `#`s).
    - Each scenario uses `#### Scenario: <name>` (exactly 4 `#`s — using 3
      or bullets will fail silently).
    - Every requirement MUST have at least one scenario.
    - Use SHALL / MUST (avoid should / may).
    - Keep specs stack-agnostic; describe behavior, not implementation.

   Sizing target: 3–7 requirements per spec, 1–3 scenarios per requirement.

7. **Validate**

   ```bash
   openspec validate --specs
   ```

   On failure, drill into the offending spec with
   `openspec validate <name> --type spec`, fix, repeat until all pass.

   Common parser failure modes:
    - Missing `## Purpose` section.
    - Scenario heading at 3 `#` instead of 4.
    - Requirement with zero scenarios.
    - Duplicate requirement names within a file.

8. **Summary**

   Report:
    - Counts: specs written, total requirements, total scenarios.
    - Table mapping capability → requirement count.
    - Capabilities where the Explore agent made informed guesses rather than
      reading code (flagged as "verify against handlers").
    - Suggested next step: review `git status`, sanity-check a few specs
      against actual handlers, then commit `openspec/`.

**Guardrails**
- Specs describe **current behavior**, not aspirations. Don't invent
  requirements that aren't in the code.
- Never overwrite a non-empty `context:` in `config.yaml` without asking.
- Never delete specs; "Overwrite all" must back up `openspec/specs/` to
  `openspec/specs.bak-<date>/` first.
- If the Explore agent returns fewer than 3 capabilities or the project
  structure is unrecognizable, stop and ask the user rather than guess.
- Do not report "onboarding complete" while any spec is invalid.

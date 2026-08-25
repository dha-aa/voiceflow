# Change Documentation Workflow

Every meaningful VoiceFlow change must leave the repository understandable from both the current implementation and its historical record. This applies to new features, bug fixes, refactors, configuration changes, dependency changes, build changes, and removals.

> A change is not complete until the implementation, tests, current specifications, historical change record, and relevant project documentation agree.

## Documentation layers

Use each documentation location for its intended purpose. Do not duplicate the same document across multiple locations.

| Location | Role | Update rule |
| --- | --- | --- |
| `specs/` | Current source of truth for the seven implementation areas and their acceptance criteria. | Update when current behavior, requirements, architecture, dependencies, file paths, or verification expectations change. |
| `spec_changes/` | Sequential historical record of completed changes. | Add one numbered Markdown file for every meaningful feature, fix, refactor, or configuration change. |
| `docs/` | Stable cross-cutting knowledge such as architecture, testing, release, privacy, and development workflow. | Update when project structure, commands, external integrations, build/release workflow, or engineering policy changes. |
| `README.md` | Concise project orientation and entry points for developers and users. | Update only when the project overview, setup, primary commands, or user-facing behavior needs to change. |
| `AGENTS.md` | Rules that AI agents must follow while modifying the repository. | Update when agent workflow, repository hygiene, verification, or documentation policy changes. |

## Feature flags

Any feature flag, rollout switch, kill switch, remotely controlled behavior, or persisted enable/disable setting must be documented in the relevant current specification and the historical `spec_changes` record. Record the flag name, owner, purpose, default state, affected behavior, rollout or exposure rules, telemetry or observability expectations, rollback/disable procedure, and removal or sunset condition. A flag must not become a permanent undocumented branch.

When a feature flag changes user-facing behavior, tests must cover both enabled and disabled paths unless the flag is deliberately test-only. The change record must state whether the flag is temporary, permanent configuration, or scheduled for removal.

## Migrations and compatibility

Any migration of persisted settings, Keychain items, model metadata, downloaded files, configuration keys, serialized data, or public interfaces must document the old and new formats, how migration is detected, whether it is automatic or user-triggered, idempotency, failure handling, backup or rollback behavior, compatibility window, and removal criteria for legacy support.

Migration code must be tested with representative pre-migration data and already-migrated data. If no rollback is technically possible, document that limitation and the recovery path. Do not remove legacy handling until the documented compatibility window has ended.

## Required workflow

### 1. Before editing

Read `AGENTS.md`, the relevant current specification, and the nearest architecture or testing documentation. Inspect the existing implementation, search for usages and tests, and identify whether the change affects other specifications or documentation.

Do not create a new abstraction, parallel implementation, or documentation file until searching for an existing one.

### 2. During implementation

Keep the change focused. Reuse existing interfaces and utilities. Preserve existing behavior unless the request explicitly changes it. Remove obsolete code created by the change instead of leaving compatibility copies, dead branches, commented-out code, or temporary debugging artifacts.

### 3. After implementation

Update the relevant current specification when the implementation or intended behavior has changed. Add the next sequential `spec_changes/` record. Update `docs/architecture.md`, `docs/testing.md`, `docs/release.md`, `README.md`, or another relevant document when the change affects that document’s subject.

Tests are part of the change record. Add or update tests for important behavior, and describe the validation performed in the historical record.

### 4. Before claiming completion

Run the smallest relevant test suite first. Run broader tests when shared infrastructure or cross-module behavior is affected. Build the application when source or project configuration changes. Also run `git diff --check`, inspect the final diff, verify that no obsolete implementation remains, and confirm that unrelated user files are not staged.

Do not claim that tests, builds, or manual verification passed unless they were actually run.

### 5. Before committing

Run the repository documentation verifier:

```bash
./scripts/verify-change-documentation.sh
```

The verifier checks staged changes for a numbered `spec_changes/` record, validates the required record sections, checks feature-flag and migration sections when those patterns are changed, and runs `git diff --cached --check`. It is safe to run repeatedly and does not modify files.

For automatic local enforcement, install the repository hook path once:

```bash
git config core.hooksPath .githooks
```

The hook invokes the same verifier before every commit. CI or another automated environment can call the script directly without changing Git configuration. The implementation lives in `scripts/verify-change-documentation.sh`, and the optional hook wrapper lives in `.githooks/pre-commit`. Neither file changes application behavior.

Confirm that the following are synchronized:

- The implementation and its tests.
- The relevant current file in `specs/`.
- The new sequential file in `spec_changes/`.
- Relevant cross-cutting documentation in `docs/`.
- The project overview or contributor guidance, when applicable.

Stage only intended files. Never stage Xcode user data, local probes, credentials, generated artifacts, or unrelated work.

## `spec_changes` record template

Create the next available sequential file using a descriptive name, for example `spec_changes/030_model-loading-refinement.md`. Include the `## Feature flags` section when the change adds or changes a flag, toggle, rollout, or kill switch. Include the `## Migration` section when the change migrates persisted data, configuration, models, files, Keychain entries, or interfaces. The automated verifier requires these sections when it detects the corresponding patterns in staged additions.

```markdown
# Change 030: <short title>

## Date
YYYY-MM-DD

## Status
Implemented and verified

## Reason
Why the change was needed.

## Scope
Affected files, modules, and behavior.

## Implementation
What changed, which existing abstractions were reused, and any important design decision.

## Behavior and compatibility
What remains unchanged and any intentional behavior differences.

## Tests and verification
List targeted tests, full tests, build commands, manual checks, and their actual results.

## Documentation updated
List the current specifications and project documentation synchronized by this change.

## Feature flags
Document flag name, default, rollout, rollback, observability, and sunset/removal criteria, or state `Not applicable`.

## Migration
Document old/new formats, detection, idempotency, failure handling, rollback/recovery, compatibility window, and legacy-removal criteria, or state `Not applicable`.

## Known limitations or follow-up
Remaining risks, deferred work, or explicit reasons for keeping any temporary element.
```

## Automated verification behavior

The verifier is intentionally dependency-free and checks only staged content. It:

1. Runs `git diff --cached --check`.
2. Detects whether staged implementation, test, specification, project, script, or workflow files require a numbered `spec_changes/NNN_*.md` record.
3. Requires the next sequential change number and validates the core record headings.
4. Requires a `## Feature flags` section when staged application or workflow changes contain feature-flag, rollout, kill-switch, or persisted enable/disable patterns.
5. Requires a `## Migration` section when staged changes contain migration, legacy, schema-version, backfill, or compatibility-window patterns.

The checker is deliberately conservative. If its pattern detection produces a false positive, document the reason in the change record rather than bypassing the hook. If it produces a false negative, the reviewer remains responsible for checking the workflow manually.

## Choosing what to update

Use this decision rule:

| Change type | Required records |
| --- | --- |
| New or changed user-facing behavior | Relevant `specs/` file, new `spec_changes/` record, tests, and user-facing or workflow docs as applicable. |
| Bug fix with no intended behavior change | New `spec_changes/` record, regression tests, and the relevant `specs/` file if it was inaccurate or incomplete. |
| Architecture or module-boundary change | New `spec_changes/` record, `docs/architecture.md`, affected current specifications, and tests. |
| Build, release, dependency, or command change | New `spec_changes/` record plus the relevant README, contributor, testing, release, or configuration documentation. |
| Removal of a feature or file | New `spec_changes/` record, removal or correction of stale references in current specifications and docs, and tests updated or removed only when they cover removed behavior. |
| Documentation-only policy change | Update `AGENTS.md` or the relevant policy document, and add a `spec_changes/` record only when the policy materially changes project workflow. |
| Feature flag or rollout change | Relevant current specification, `spec_changes/` record with a `## Feature flags` section, enabled/disabled tests, rollback and sunset documentation, and relevant user-facing or operations documentation. |
| Data, settings, model, file, Keychain, or interface migration | Relevant current specification, `spec_changes/` record with a `## Migration` section, pre- and post-migration tests, failure/recovery behavior, compatibility window, and removal criteria for legacy support. |

The goal is not to write more documentation. The goal is to keep a small, discoverable set of documents accurate, complementary, and sufficient for the next human or AI agent to understand, modify, test, and safely remove the change.

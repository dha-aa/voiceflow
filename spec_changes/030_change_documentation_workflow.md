# Change 030: Change Documentation Workflow

## Date
2026-08-25

## Status
Implemented and verified

## Reason
Future feature work, bug fixes, refactors, and configuration changes need a consistent documentation trail. The repository must preserve both an accurate current source of truth and a concise historical explanation of what changed, why it changed, and how it was verified.

## Scope
This policy applies to all meaningful VoiceFlow changes, including user-facing behavior, architecture, module boundaries, dependencies, build and release workflow, commands, configuration, removals, and documentation policy.

## Implementation
Added `docs/change-documentation.md`, which defines the complementary roles of `specs/`, `spec_changes/`, `docs/`, `README.md`, and `AGENTS.md`. It also defines the required before-edit, during-implementation, after-implementation, verification, and pre-commit workflow, together with a standard `spec_changes` template and change-type decision table.

Updated `AGENTS.md` to link directly to the workflow document so future AI agents discover it before editing or adding features.

## Behavior and compatibility
This is a documentation-only policy change. It does not alter VoiceFlow application behavior, runtime dependencies, build settings, or user-facing functionality.

## Tests and verification
Ran `git diff --check` after creating the documents. No application build or test run was required because this change only adds and updates Markdown guidance.

## Documentation updated

- `AGENTS.md`
- `docs/change-documentation.md`
- `spec_changes/030_change_documentation_workflow.md`

## Known limitations or follow-up
Future changes must apply this workflow and add the next sequential `spec_changes` record when the change materially affects project behavior, architecture, tooling, or engineering workflow.

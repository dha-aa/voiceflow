# Change 031: Change Documentation Verifier

## Date
2026-08-25

## Status
Implemented and verified

## Reason
The documentation workflow should be easy to follow and difficult to forget. A lightweight automated check provides an early warning when implementation changes are missing a historical change record, required record headings, or feature-flag and migration documentation.

## Scope
This change affects repository workflow only. It covers staged-change validation, sequential `spec_changes` records, feature-flag and migration coverage, whitespace checks, and optional local Git pre-commit enforcement.

## Implementation
Added `scripts/verify-change-documentation.sh`. The dependency-free Bash verifier checks staged content, runs `git diff --cached --check`, requires a numbered sequential `spec_changes` record for implementation and workflow changes, validates the core record headings, and requires `## Feature flags` or `## Migration` sections when semantic patterns are detected.

Added `.githooks/pre-commit`, which invokes the verifier. Developers opt in once with `git config core.hooksPath .githooks`; CI can invoke the script directly.

Expanded `docs/change-documentation.md` with feature-flag requirements, migration and compatibility requirements, verifier behavior, hook setup, and false-positive/false-negative guidance.

## Behavior and compatibility
This change does not alter VoiceFlow runtime behavior, application binaries, user data, or build settings. The hook is opt-in and does not modify a developer’s Git configuration automatically.

## Tests and verification
Ran `git diff --check` and executed `./scripts/verify-change-documentation.sh` with no staged changes. The verifier returned the expected no-op result. The staged positive and negative checks should be run by contributors or CI when the hook is installed.

## Documentation updated

- `docs/change-documentation.md`
- `spec_changes/031_change_documentation_verifier.md`
- `AGENTS.md` remains the entry point and links to the workflow document.

## Feature flags
Not applicable. No application feature flag or rollout behavior changed.

## Migration
Not applicable. No persisted data, configuration, model, file, Keychain, or interface migration changed.

## Known limitations or follow-up
Pattern detection is intentionally conservative and can produce false positives or miss unusual terminology. Reviewers remain responsible for confirming documentation completeness. The hook is opt-in because repository-level Git configuration is local developer state.

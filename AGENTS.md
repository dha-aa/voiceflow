# AI-Friendly Codebase Maintenance Rules

This codebase is becoming larger and more complex. From now on, treat **maintainability, clarity, and AI-agent efficiency as first-class requirements**.

The goal is to keep the repository easy for both humans and AI coding agents to understand, navigate, modify, test, and extend without wasting unnecessary tokens.

## 1. Understand Before Changing

Before modifying code:

1. Identify the relevant files and modules.
2. Search for existing implementations and usages.
3. Understand how the current implementation works.
4. Follow existing architecture and conventions.
5. Do not create a new abstraction if an existing one already solves the problem.

Never make architectural changes based on assumptions.

## 2. Keep the Codebase Modular

* Keep files focused on a single responsibility.
* Avoid unnecessarily large files.
* Split large modules when they contain unrelated responsibilities.
* Keep business logic separate from UI, infrastructure, configuration, and utilities where appropriate.
* Prefer small, composable functions and components.
* Avoid deeply nested or unnecessarily complicated logic.
* Use clear and predictable naming.

The repository structure should make it obvious where an AI agent should look for a particular feature.

## 3. Optimize for AI Navigation

The codebase must be easy for an AI coding agent to navigate.

* Use predictable folder and file names.
* Keep related functionality together.
* Avoid unnecessary abstractions and indirection.
* Avoid duplicate implementations of the same concept.
* Keep public interfaces clear.
* Prefer explicit code over clever or implicit behavior.
* Maintain clear entry points for major systems.
* Do not scatter one feature across many unrelated locations without a good reason.

An AI agent should be able to answer:

> "Where is this functionality implemented?"

quickly by inspecting the repository structure.

## 4. Remove Dead Code Aggressively

Dead code must not accumulate.

Remove:

* Unused files
* Unused functions
* Unused classes
* Unused variables
* Unused imports
* Unused components
* Unused configuration
* Unused dependencies
* Obsolete APIs
* Deprecated implementations that are no longer required
* Commented-out code
* Old debugging code
* Duplicate implementations
* Temporary workarounds that are no longer necessary

Do not keep code "just in case."

If something is no longer used and there is no documented reason to keep it, remove it.

## 5. Avoid Duplicate Logic

Before implementing something new:

1. Search the repository for similar functionality.
2. Reuse existing utilities, services, components, or abstractions when appropriate.
3. If multiple implementations solve the same problem, consolidate them when safe.

Do not create:

```text
utils2
helperNew
serviceV2
componentFinal
componentFinalNew
```

just because the existing implementation is inconvenient.

Improve the existing implementation when appropriate.

## 6. Documentation Rules

Documentation should help an AI agent understand the system quickly.

Maintain a small amount of **high-value documentation** rather than documenting every obvious line of code.

At minimum, maintain documentation for:

* Overall architecture
* Important directories
* Major modules
* Core workflows
* Important design decisions
* External integrations
* Environment/configuration requirements
* Development commands
* Testing commands
* Build/release process
* Important constraints or limitations

Documentation should explain **why**, not merely repeat **what the code already says**.

Bad:

> This function records audio.

Good:

> Audio recording starts when the global Fn key is pressed and stops on release. The recorder passes the final buffer to the transcription pipeline; it must not perform transcription itself.

## 7. Keep Documentation Synchronized

Documentation is part of the codebase.

Whenever you change:

* Architecture
* APIs
* Commands
* Configuration
* Folder structure
* Development workflow
* Build process
* User-facing behavior
* Important technical decisions

check whether the relevant documentation needs to be updated.

Never leave documentation describing functionality that no longer exists.

When functionality is removed, remove or update its documentation too.

## 8. Maintain an Architecture Map

Keep a concise architecture document that allows an AI agent to understand the repository without reading the entire codebase.

It should answer:

* What is this project?
* What are the major modules?
* Where is the application entry point?
* Where does business logic live?
* Where does UI logic live?
* Where are external integrations?
* Where are tests?
* How does the main data flow work?
* Which modules are allowed to depend on which other modules?

Keep this document concise and update it when architecture changes.

For the required workflow for synchronizing current specifications, historical `spec_changes/` records, tests, and project documentation, read [`docs/change-documentation.md`](docs/change-documentation.md) before editing or adding a feature.

## 9. Comments

Do not add comments for obvious code.

Avoid:

```swift
// Increment counter
counter += 1
```

Prefer comments that explain:

* Why something is necessary
* Non-obvious behavior
* Important constraints
* Workarounds
* External API limitations
* Architectural decisions

If the code needs a large comment to explain what it does, consider whether the code itself should be refactored.

## 10. Dependencies

Before adding a dependency:

1. Check whether the project already has something that solves the problem.
2. Check whether the standard library/platform APIs are sufficient.
3. Check whether an existing internal utility can be reused.

Do not add dependencies unnecessarily.

When a dependency is removed, remove its configuration and documentation as well.

## 11. Refactoring Rules

When modifying an existing area:

* Prefer improving the existing implementation over creating a parallel implementation.
* Remove obsolete code created by the refactor.
* Do not leave temporary compatibility layers without a reason.
* Keep refactors scoped to the problem.
* Avoid unrelated rewrites.
* Preserve existing behavior unless the task explicitly requires behavior changes.

A refactor is not complete if the old implementation remains unnecessarily.

## 12. Testing

When behavior changes:

* Find existing tests first.
* Update existing tests when appropriate.
* Add tests for important new behavior.
* Never delete tests simply because they currently fail.
* Run the smallest relevant test suite first.
* Run broader validation when the change affects shared infrastructure.

Tests should document important expected behavior.

## 13. Verification

Before considering a task complete, verify:

1. The implementation works.
2. The project builds.
3. Relevant tests pass.
4. There are no obvious unused imports or variables.
5. No unnecessary files were introduced.
6. No obsolete implementation remains.
7. Documentation is still accurate.
8. The final architecture remains understandable.

Do not claim a change is complete without performing appropriate verification.

## 14. Keep Changes Focused

Do not make unrelated changes while implementing a feature.

Avoid turning:

> "Add feature X"

into:

> "Rewrite half of the application."

However, if the requested change exposes obvious dead code or a small architectural problem directly related to the work, clean it up when it is safe and clearly beneficial.

## 15. AI Agent Token Efficiency

AI agents should not read the entire repository unnecessarily.

Prefer:

1. Inspect repository structure.
2. Identify relevant modules.
3. Search for the relevant symbol/function/feature.
4. Read only the necessary files.
5. Trace dependencies only when required.
6. Make the smallest correct change.
7. Run targeted verification.
8. Update documentation if necessary.

Avoid repeatedly loading large unrelated files.

Keep important information close to where it is needed and maintain concise architecture documentation so agents can orient themselves quickly.

## 16. Before Creating Anything New

Before creating a new:

* File
* Function
* Component
* Service
* Utility
* Abstraction
* Dependency
* Documentation file

ask:

> Does this already exist somewhere?

Search first.

If something similar exists, determine whether it should be reused, extended, or refactored instead.

## 17. Repository Hygiene

The repository should not contain:

* Temporary files
* Debug artifacts
* Generated files that should not be committed
* Duplicate implementations
* Abandoned experiments
* Old documentation
* Unused dependencies
* Commented-out implementations
* Misleading filenames
* Stale configuration

Keep the repository production-ready.

## 18. Decision Rule for AI Agents

When there are multiple possible implementations, prefer the solution that is:

1. Simplest
2. Most consistent with the existing architecture
3. Easiest for another developer or AI agent to understand
4. Least duplicated
5. Easiest to test
6. Least dependent on unnecessary abstractions
7. Least expensive in future maintenance

Do not optimize for cleverness.

Optimize for **clarity and maintainability**.

## 19. Definition of Done

A task is not finished merely because the requested code works.

A task is finished when:

* The feature works.
* Existing behavior is preserved where required.
* Relevant tests pass.
* No unnecessary dead code remains.
* No unnecessary duplicate implementation was introduced.
* The code follows the existing architecture.
* The repository remains easy to navigate.
* Relevant documentation is updated.
* The change can be understood by another AI agent without requiring unnecessary repository-wide investigation.

**Core principle:**

> Write code that the next human or AI agent can understand quickly, modify safely, test confidently, and remove cleanly when it is no longer needed.

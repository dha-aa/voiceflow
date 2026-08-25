# Change 024: Privacy-First Local Snippets

## Summary

VoiceFlow now supports reusable local snippets for frequently spoken personal, work, and everyday phrases. A snippet has a **name**, a **trigger phrase**, and a **value**. Users manage snippets from a dedicated **Settings → Snippets** pane, and configured triggers are expanded locally immediately before text injection.

The feature does not add a special voice command and does not create an AI request. Stored snippet values remain outside all provider requests, logs, screen-context payloads, and transcription diagnostics.

## User workflow

The user opens **Settings → Snippets**, chooses **Add**, and enters a name, trigger, and value. Examples include `My Email` / `my email` / `user@gmail.com`, `My Phone` / `my phone number` / `+91 XXXXX XXXXX`, or a frequently used message or URL. Existing snippets can be edited or deleted. A new installation starts with an empty snippet list; no personal examples are pre-populated.

During dictation, no special command is required. A trigger can appear by itself or naturally inside a sentence. For example, with the trigger `my email` and value `user@gmail.com`, the local expansion of:

> You can contact me at my email address.

is:

> You can contact me at user@gmail.com address.

Only the configured trigger is replaced. If the user wants the entire phrase replaced, they can configure `my email address` as the trigger.

## Architecture and source of truth

The feature is implemented in `voiceflow/Core/Transcription/SnippetStore.swift`.

`Snippet` is a `Codable`, `Equatable`, `Identifiable` value type containing:

| Field | Type | Behavior |
|---|---|---|
| `id` | `UUID` | Stable identity used by Settings CRUD. |
| `name` | `String` | User-facing label; trimmed on add/update. |
| `trigger` | `String` | Phrase recognized in normalized or AI-returned text; trimmed on add/update. |
| `value` | `String` | Local replacement text; retained as entered and never logged. |

`SnippetStore` is an observable shared store. The application composition root creates one instance in `AppDelegate` and passes it to both `MenuBarController`/Settings and `TranscriptionCoordinator`. Consequently, CRUD changes are immediately used by live dictation without recreating the application pipeline.

## Persistence and CRUD

Snippets are encoded as JSON and persisted in `UserDefaults` under the key `voiceFlowSnippets`. The store filters unusable decoded entries when loading. Add and update require a non-empty trimmed name and trigger and a non-empty value. Delete removes the matching identifier and persists the remaining list. The feature is local application data and is not represented as a Keychain secret; the Settings pane explains that values are kept locally and are not sent to Claude, ChatGPT, or another network service.

`SnippetsSettingsView` provides the dedicated list and Add/Edit form, including name, trigger, and value fields, Save/Cancel controls, and delete confirmation. Invalid save operations are disabled in the UI. The view is rendered from the new `.snippets` Settings destination and uses the shared store.

## Matching and replacement semantics

`SnippetStore.expand(_:)` performs synchronous, local string replacement:

1. Each trigger is escaped before being used as a regular-expression pattern.
2. Matching is case-insensitive.
3. Matching is whole-phrase based and requires a non-letter/non-number/non-underscore boundary on both sides. Therefore `my email` matches in a sentence and after punctuation, but does not match inside `my emails`.
4. Multi-word triggers are supported.
5. All candidate matches are collected from the original text, ordered by location, and overlapping matches are filtered before mutation.
6. For overlapping triggers beginning at the same location, the longer trigger wins. For example, `my email address` wins over `my email`.
7. Non-overlapping matches are all expanded. Replacements are applied from the end of the string toward the beginning so earlier ranges remain valid.

Replacement values are inserted literally; they are not recursively re-expanded during the same pass. This keeps expansion deterministic and prevents an inserted value from unexpectedly acting as another trigger.

## Pipeline placement and privacy contract

The production pipeline remains:

> Local STT → `TextProcessor` normalization → optional Claude command/Always Use AI/Grammar Fix → local `SnippetStore.expand` → injection

The expansion occurs in `TranscriptionCoordinator` after `ClaudeCommandProcessor.processTranscribedText` returns and before `onTranscriptionComplete` is invoked. This placement is deliberate:

- For ordinary dictation, the locally recognized trigger is replaced before injection.
- With Grammar Fix enabled, the provider receives the original normalized text; the stored value is applied only after the corrected response returns.
- With an explicit AI prefix or Always Use AI, the provider receives the command/original text and never the stored replacement value. Any configured trigger present in the final AI response is also expanded locally before injection, as the final output stage is the defined snippet boundary.
- Snippet configuration alone never enables AI, invokes a provider, captures screen context, reads selected text, or creates a network request.
- Diagnostics continue to report only identifiers, states, character counts, and timing. Snippet names, triggers, and values are not logged.

The existing AI-prefix precedence, Grammar Fix behavior, Always Use AI opt-in semantics, selection-aware privacy, model readiness, local transcription, text injection, and overlay state flow are otherwise unchanged.

## Settings navigation and composition changes

The Settings destination list now includes `.snippets` between Models and About. `SettingsView`, `SettingsWindowController`, `MenuBarController`, `MenuBarPopoverView`, and `AppDelegate` pass the shared `SnippetStore` through the existing settings-opening path. Existing callers that construct these components without an explicit store remain source-compatible through default store parameters, while production uses one shared instance.

## Acceptance criteria

| Area | Acceptance criterion |
|---|---|
| Settings | A dedicated Snippets pane is selectable and constructible from Settings. |
| Add | A valid name, trigger, and value can be added and is immediately visible. |
| Edit | An existing snippet can be updated by stable identifier and the update is persisted. |
| Delete | A snippet can be deleted with confirmation and disappears immediately. |
| Persistence | A new `SnippetStore` reading the same `UserDefaults` suite restores the saved CRUD state. |
| Natural use | A trigger expands when spoken alone or inside a sentence without a special command. |
| Matching | Matching is case-insensitive, supports multi-word phrases, respects whole-word boundaries, and handles punctuation boundaries. |
| Overlap | A longer trigger at the same location takes precedence over a shorter overlapping trigger. |
| Injection | Expansion occurs before the final injection callback, so injected text contains the configured value. |
| AI privacy | Always Use AI/provider requests contain the original trigger text and do not contain the stored value. |
| Network behavior | Snippets do not independently create provider or other network requests. |
| Logging | Snippet values and full dictated text are absent from diagnostics. |
| Compatibility | Existing model, recording, transcription, injection, AI, selection, onboarding, and Settings behavior remains intact. |

## Verification evidence

The test-first sequence was completed as follows:

- The unchanged pre-Snippets baseline completed with **166 XCTest tests and zero failures**.
- New red tests were added before implementation for natural expansion, boundaries, overlap precedence, Settings navigation/CRUD persistence, and the AI privacy pipeline.
- Focused Snippets validation completed with **20 tests and zero failures**.
- The full `voiceflowTests` suite completed with **172 tests and zero failures**.
- The existing core pipeline integration test was isolated from shared `UserDefaults` AI settings so prior AI tests cannot accidentally enable Always Use AI and induce a real provider request. This is test isolation only; production preferences and behavior were not disabled or changed.

The tests use injected providers, isolated `UserDefaults` suites, and temporary model fixtures. They verify replacement behavior and provider-input privacy deterministically without sending real snippet values to an AI service or requiring large model downloads.

## Files

| Path | Purpose |
|---|---|
| `voiceflow/Core/Transcription/SnippetStore.swift` | Snippet model, JSON persistence, CRUD, and local expansion engine. |
| `voiceflow/Core/Transcription/TranscriptionCoordinator.swift` | Applies local expansion after optional AI processing and before injection. |
| `voiceflow/UI/Settings/SnippetsSettingsView.swift` | Dedicated Snippets CRUD UI and local-only privacy explanation. |
| `voiceflow/UI/Settings/SettingsView.swift` | Adds the `.snippets` destination and pane. |
| `voiceflow/UI/Settings/SettingsWindowController.swift` | Preserves the shared store when opening or refreshing Settings. |
| `voiceflow/UI/MenuBar/MenuBarController.swift` | Passes the shared store into the popover. |
| `voiceflow/UI/Popover/MenuBarPopoverView.swift` | Passes the shared store into the Settings action. |
| `voiceflow/App/AppDelegate.swift` | Creates and shares the production store. |
| `voiceflowTests/Transcription/TextProcessorTests.swift` | Expansion semantics, boundaries, case handling, and overlap tests. |
| `voiceflowTests/UI/SettingsTests.swift` | Navigation, view construction, and persistence tests. |
| `voiceflowTests/Transcription/TranscriptionCoordinatorTests.swift` | AI privacy and final pre-injection expansion regression test. |
| `voiceflowTests/Injection/CorePipelineIntegrationTests.swift` | Isolated AI defaults for deterministic existing integration coverage. |

## Known boundary

Snippet values are reusable local application data, not a secure secret vault. They are displayed in the Snippets management UI and are stored in the app’s `UserDefaults` JSON record. Users should not use this feature for credentials or other values that require Keychain protection.

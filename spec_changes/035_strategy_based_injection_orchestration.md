# Change 035: Strategy-Based Injection Orchestration

## Date
2026-08-26

## Status
Implemented and verified for automated routing and build behavior; application-specific manual coverage remains partial.

## Reason
The attachment proposed isolating text-injection mechanisms behind strategies so the system can add or tune target capabilities without turning `TextInjector` into one large application-specific conditional. VoiceFlow already had injectable paste and keyboard seams, but their route selection was still embedded in the injector. This change introduces a small, testable strategy boundary while preserving the existing safety contract.

## Scope
The change affects the Injection Core module, focused injection tests, the current text-injection specification, the architecture map, and the testing guide. It does not change transcription, target capture timing, application state ownership, completion feedback, permissions, logging privacy rules, or persisted settings.

## Implementation
Added `InjectionContext` and `TextInjectionStrategy` in `voiceflow/Core/Injection/InjectionStrategy.swift`. Added focused strategy implementations in `voiceflow/Core/Injection/InjectionStrategies.swift`:

- `TerminalPasteStrategy` handles only a frontmost recognized terminal.
- `AccessibilityValueStrategy` performs AX value replacement.
- `ClipboardPasteStrategy` handles only a frontmost non-terminal target.
- `KeyboardTypingStrategy` posts Unicode events to the captured process identifier.

`TextInjector` now captures the target process identifier, bundle identifier, terminal classification, and frontmost state once per attempt, then runs the ordered strategy list. A second named Accessibility strategy is retained as the existing recovery attempt after keyboard failure. Existing protocols and constructor seams remain available to tests and `InjectionCoordinator`.

The proposed `FocusedElementInspector`, application-specific capability allowlist, and universal post-injection verifier were not added. The current `hasTextInput(in:)` capability check remains the coordinator boundary, and a verifier that reads target content after paste would need careful handling for privacy, selection replacement, asynchronous editor state, and controls that do not expose readable AX values.

## Behavior and compatibility
The route order is unchanged in behavior: frontmost terminal paste first, AX replacement, frontmost non-terminal paste, captured-process keyboard events, then AX recovery. Terminal paste still restores all pasteboard item data, moves the caret with Control-E, and never presses Enter. Global paste remains prohibited when the captured target is no longer frontmost. Explicit Accessibility trust remains mandatory.

The proposal’s recommendation to recapture the focused target immediately before injection is intentionally not adopted. VoiceFlow captures the application at Fn-down to prevent a focus race from redirecting output to a new application. The strategy context therefore represents the original captured target and its safety-approved frontmost snapshot rather than silently replacing it.

The proposal’s separate `InjectionState` is also not adopted because `AppStateManager` is already the single source of truth for visible pipeline states. Adding a second state machine would create duplicate ownership and possible disagreement between overlay and pipeline behavior.

## Tests and verification
The focused `TextInjectorTests` suite passed with 17 tests and 0 failures after the strategy extraction and route-selection test addition. The full `voiceflowTests` target passed with 192 tests and 0 failures. `git diff --check` and the repository documentation verifier passed. A clean `./scripts/buildapp.sh --clean` build remains the final local artifact check for this change. Existing regression coverage continues to verify terminal routing, clipboard fallback, non-frontmost safety, clipboard restoration, AX selection/caret helpers, capability classification, and error handling.

## Documentation updated
Updated `specs/spec_04_text_injection.md` with the strategy components, immutable context, ordered strategy list, and intentional exclusions. Updated `docs/architecture.md` to expose the injection strategy boundary in the module map and data flow. `docs/testing.md` will document the strategy route-selection test alongside the existing injection matrix.

## Feature flags
Not applicable. No rollout flag, kill switch, or persisted enable/disable setting was added or changed.

## Migration
Not applicable. No settings, Keychain entries, model files, serialized data, or public interfaces require migration.

## Known limitations or follow-up
Strategy selection is now isolated, but live editor compatibility still depends on each application’s Accessibility exposure, paste handling, focus behavior, and synthetic-event acceptance. Manual tests remain necessary for TextEdit, Notes, Safari, other installed browsers, Electron editors, secure/token fields, and terminal variants. A future verification layer should only be added with a privacy-preserving result contract and an explicit policy for cases where the target cannot expose readable post-injection state.

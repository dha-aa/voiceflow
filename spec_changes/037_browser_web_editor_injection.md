# Change 037: Browser web-editor injection compatibility

## Date
2026-08-27

## Status
Implemented and verified by focused/full automated tests and a fresh direct app build; application-specific live coverage remains dependent on the user’s installed browser pages.

## Reason
Text injection was reported as failing in Claude Chat and Reddit. Both are web applications whose browser may expose an incomplete or unavailable focused Accessibility element even when an editable web control is visibly focused. `InjectionCoordinator` interpreted that lookup failure as no supported text input and copied the output without invoking `TextInjector`, so the automatic copy-then-Command-V route was never reached.

## Scope
This change affects focused-input classification in `TextInjector`, browser bundle recognition, injection regression tests, Specification 04, and the manual testing guide. It does not change transcription, AI processing, target capture timing, clipboard restoration, terminal Control-E behavior, or the no-Enter rule.

## Implementation
`TextInjector.hasTextInput(in:)` now obtains the captured application bundle identifier before focused-element lookup. If the target is not a terminal and the focused AX element cannot be retrieved, a known browser that is currently frontmost is treated as an injection candidate. The supported browser identifiers include Safari, Safari Technology Preview, Chrome, Brave, Firefox, Edge, Opera, Vivaldi, and Arc.

This preserves the existing safe route: the coordinator calls `TextInjector`, the frontmost browser reaches the existing temporary clipboard writer and automatic Command-V strategy, and the strategy rechecks that the originally captured process is still frontmost immediately before posting Command-V. If focus changed, the global paste is skipped and captured-process fallbacks continue instead.

The browser allowlist is deliberately narrow and is used only for the specific case where AX focused-element lookup fails. It does not override an explicit disabled or non-settable focused element, and it does not replace capability checks when AX metadata is available.

## Behavior and compatibility
Claude Chat and Reddit compose, reply, and prompt controls in supported browsers can now reach automatic Command-V even when their focused AX element is unavailable. The old behavior remains for native controls and for browsers that expose a usable AX role/value/selection signal. A browser page with no editable control may ignore the paste; VoiceFlow does not claim success merely because the browser was classified as an injection candidate.

Accessibility trust remains required for cross-process injection. The original captured application remains the only target. Clipboard contents are still restored after successful or failed temporary paste, and unsupported/read-only controls continue to use the coordinator’s explicit clipboard-copy mode.

## Tests and verification
Added `TextInjectorTests` coverage for known browser bundle identifiers and non-browser rejection. The focused `TextInjectorTests` plus `InjectionCoordinatorTests` run passed with exit status 0. The full `voiceflowTests` suite passed with exit status 0. `./scripts/buildapp.sh --clean` passed and refreshed `build/VoiceFlow.app` at 2026-08-27 10:19. Existing Swift 6 migration warnings in `AppStateManagerTests.swift` remain warnings and were not introduced by this change. Manual verification must use the exact rebuilt `build/VoiceFlow.app` with Accessibility/Input Monitoring permission granted to that build and must test disposable fields in Claude Chat and Reddit without submitting content.

## Documentation updated
`specs/spec_04_text_injection.md` documents the known-browser fallback and its safety limits. `docs/testing.md` adds Claude Chat and Reddit to the browser-editor verification matrix. This historical record documents the diagnosis and design decision.

## Feature flags
Not applicable. No rollout flag, kill switch, or persisted enable/disable setting was added or changed.

## Migration
Not applicable. No settings, Keychain entries, model files, serialized data, or public interfaces require migration.

## Known limitations or follow-up
The browser application must still be frontmost when the output is delivered, and macOS Accessibility/Input Monitoring permissions must be granted to the exact VoiceFlow build being tested. Some browser editors, rich-text surfaces, or content-security configurations may reject synthetic Command-V or expose a browser-specific control that ignores paste. Manual results must therefore be recorded per browser and control; support for Claude Chat or Reddit must not be generalized to every web application.

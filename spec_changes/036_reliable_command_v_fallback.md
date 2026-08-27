# Change 036: Reliable Command-V Fallback

## Date
2026-08-26

## Status
Implemented and verified by automated tests and clean build; application-specific manual coverage remains dependent on the user’s installed targets.

## Reason
The frontmost clipboard fallback could be ineffective for controls that exposed incomplete Accessibility metadata, could race pasteboard propagation, and did not restore the previous clipboard if the temporary clipboard write failed after clearing the pasteboard. The user also requested that compatible text controls use Command-V after transcription, while retaining captured-target safety.

## Scope
This change affects focused-input capability classification, temporary paste timing and restoration, live frontmost validation, injection regression tests, Specification 04, and the testing guide. It does not change transcription, target capture timing, permissions, terminal caret behavior, or the clipboard-copy path for unsupported/read-only targets.

## Implementation
`TextInjector.isSupportedTextInput` now treats recognized text roles—including text fields, text areas, search fields, web areas, combo boxes, secure fields, and token fields—as eligible for the normal paste fallback when the control is enabled and is not explicitly reported as non-settable. A usable string AX value or selected range still enables more precise AX replacement. This lets incomplete browser/custom AX elements reach the frontmost paste strategy instead of being prematurely classified as no-input.

`SystemTextPaster` now waits approximately 20 ms after writing temporary output so the target application can observe the updated pasteboard before Command-V. The pasteboard snapshot is restored for clipboard-write failures as well as paste-command and terminal caret-command failures. Each global paste strategy performs a second frontmost check immediately before posting Command-V; if the captured target has lost focus, it skips global paste and allows the process-targeted keyboard fallback.

## Behavior and compatibility
For frontmost non-terminal targets, the route now explicitly starts with temporary clipboard write plus automatic Command-V, followed by AX replacement, captured-process keyboard events, and Accessibility recovery. Terminals continue to use Command-V plus Control-E, clipboard restoration, and no Enter. No global paste is sent to a different application after the target changes. Explicitly disabled and explicitly read-only controls remain excluded from direct injection and use clipboard delivery through `InjectionCoordinator`.

This change improves compatibility for controls with incomplete AX metadata but cannot force applications that reject paste, synthetic events, or custom editor input. Command-V is only a universal fallback for a currently frontmost, captured target; it is not sent blindly to arbitrary applications or read-only controls.

## Tests and verification
The baseline injector/coordinator run passed with 25 tests and 0 failures before editing. The focused post-change `TextInjectorTests` run passed with 19 tests and 0 failures, including live frontmost loss and clipboard-write failure restoration. The full `voiceflowTests` target passed with 194 tests and 0 failures. The current routing refinement keeps the same test seams and makes the frontmost copy-then-Command-V-first order explicit; it requires the focused and full suites to be rerun before commit. The clean app build previously passed and produced `build/VoiceFlow.app`.

## Documentation updated
`specs/spec_04_text_injection.md` documents the broader role fallback, pasteboard propagation delay, live frontmost revalidation, and complete restoration behavior. `docs/testing.md` adds the updated strategy and clipboard preservation checks.

## Feature flags
Not applicable. No rollout flag, kill switch, or persisted enable/disable setting was added or changed.

## Migration
Not applicable. No settings, Keychain entries, model files, serialized data, or public interfaces require migration.

## Known limitations or follow-up
Live end-to-end application verification remains necessary. The target Mac should test TextEdit, Safari/Chrome/Firefox web controls, Electron/code editors, secure/token controls with disposable data, and each installed terminal. Record the application and control result individually. A paste command can return successfully even when an application ignores it; VoiceFlow therefore reports the route operation’s success but does not claim universal editor acceptance.

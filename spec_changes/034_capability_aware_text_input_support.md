# Change 034: Capability-Aware Text Input Support

## Date
2026-08-26

## Status
Implemented and verified for automated routing and build behavior; application-specific manual coverage remains partial.

## Reason
The previous injection layer handled the main native roles and terminal family, but it treated recognized roles as editable before checking writability. That could send an explicitly read-only control through the injection path instead of the coordinator’s clipboard-delivery path. Broader support also required a consistent capability decision for native, browser-backed, custom, secure, token, and selection-backed controls without claiming that every application implements macOS Accessibility in the same way.

## Scope
This change affects `TextInjector.hasTextInput(in:)`, its testable capability decision, focused-input routing documentation, and the manual injection test matrix. It preserves explicit Accessibility permission, captured-target safety, clipboard restoration, terminal caret normalization, no-Enter behavior, and the existing AX → paste → process-targeted keyboard route order.

## Implementation
`TextInjector` now reads the focused element’s role, enabled state, string `AXValue`, `AXValue` settable status, and selected-text range before reporting a supported text input. An explicitly disabled element or an explicitly non-settable value is rejected. A positive writable-value result or a selected range is accepted, including for custom editors that omit a string value but expose selection. When settable status cannot be queried, a string-valued recognized text role is used as a conservative fallback. Recognized role families include native text fields and areas, search fields, combo boxes, web areas, secure fields, and token fields; select-only controls remain dependent on a positive editability/selection signal.

New unit tests cover writable controls, selection-backed controls without a string value, explicit read-only values, disabled controls, static text, and empty/non-string values. The current injection test doubles and existing terminal/frontmost tests remain in use.

## Behavior and compatibility
Existing successful routes remain unchanged. Frontmost terminals continue to use temporary clipboard paste, `Command-V`, `Control-E`, clipboard restoration, and no automatic Enter. Frontmost non-terminal controls may use the clipboard-preserving paste fallback after AX mutation fails. A target that is no longer frontmost never receives global paste; only the captured-process keyboard fallback may be attempted.

The coordinator should now classify explicit read-only or disabled controls as unsupported and copy final output to the clipboard. Application-specific success is still conditional on AX exposure, paste handling, focus, permissions, and synthetic-event acceptance. This change does not introduce an application allowlist or promise universal support.

## Tests and verification
The baseline `TextInjectorTests` run completed with 14 tests and 0 failures before this change. The post-change focused run completed with 16 tests and 0 failures. The full `voiceflowTests` target completed with 191 tests and 0 failures. `./scripts/buildapp.sh --clean` completed successfully and produced `build/VoiceFlow.app`.

Live capability smoke checks were performed without reading text content. A focused TextEdit document exposed `AXTextArea`, a string value, a settable value, and a selected range. A disposable Safari page initially exposed `AXTextField`, a string value, enabled state, settable value, and selected range. The remaining controls could not be focused automatically because Safari disallowed JavaScript from Apple Events and the external probe process could not query the browser’s focused element reliably without additional Accessibility automation. Chrome, Firefox, Electron editors, and alternate terminal applications were not available or were not manually exercised. These observations validate representative AX exposure only; they do not prove end-to-end VoiceFlow injection in each application.

## Documentation updated
The current `specs/spec_04_text_injection.md` now defines capability-based detection, explicit read-only handling, selection-backed custom editors, and the expanded role families. `docs/testing.md` now includes native search/combo, secure/token, disabled/read-only, ARIA/custom web textbox, browser, Electron, terminal, and clipboard-safety scenarios.

## Feature flags
Not applicable. This is a capability-detection and routing correction with no new persisted toggle, rollout switch, or kill switch.

## Migration
Not applicable. No persisted settings, Keychain items, model files, serialized data, or public interfaces are migrated.

## Known limitations or follow-up
The macOS Accessibility API is implemented differently across applications and browsers. Automated tests validate routing decisions and safety seams, not live application behavior. The next manual verification pass should identify the application, version, macOS version, focused control type, route observed, and result for each tested control, including actual VoiceFlow output delivery. A failed editor-specific test should lead to a targeted adapter only when the behavior is reproducible and the adapter can preserve captured-target safety and clipboard privacy.

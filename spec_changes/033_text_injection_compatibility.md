# Change 033: Broaden Safe Text-Injection Compatibility

## Date

2026-08-26

## Status

Implemented and verified.

## Reason

VoiceFlow's prior output path covered AX value replacement and a terminal-specific paste route, but some native, browser-backed, Electron, and custom editable controls reject direct AX value mutation while accepting ordinary paste. The implementation also needed to ensure that a captured target changing focus could never receive a global paste intended for another application. The change broadens compatibility without claiming universal injection and preserves the existing Accessibility gate, terminal behavior, clipboard restoration, and captured-target safety.

## Scope

Affected production behavior:

- `voiceflow/Core/Injection/TextInjector.swift`
- Accessibility focused-control capability detection
- Terminal and non-terminal output route selection
- Temporary clipboard paste abstraction and caret normalization
- Frontmost-target validation for global Command-V

Affected verification and documentation:

- `voiceflowTests/Injection/TextInjectorTests.swift`
- `voiceflowTests/Injection/InjectionTestDoubles.swift`
- `specs/spec_04_text_injection.md`
- `docs/testing.md`

## Implementation

`TerminalTextPasting` and `SystemTerminalTextPaster` were generalized to `TextPasting` and `SystemTextPaster`. The paster snapshots all pasteboard item data, writes temporary output, posts Command-V, optionally posts Control-E, and restores the previous pasteboard on both success and failure. Normal paste does not post Control-E; terminal routing explicitly requests `moveCaretToEndOfLine: true`.

`TextInjector` now accepts an injected `frontmostApplicationProvider`. A frontmost terminal uses the existing paste-plus-Control-E route. A frontmost non-terminal target first receives the existing AX value replacement attempt and, if that fails, a clipboard-preserving normal paste fallback. If the target is not frontmost, VoiceFlow never sends global Command-V; it proceeds to the captured-process keyboard fallback where applicable.

Focused-input detection remains capability-based. It recognizes standard AX text roles, `AXWebArea`, writable string AX values, and selected-range-backed controls. An explicit non-settable AX value is treated as read-only so `InjectionCoordinator` can copy the final output to the clipboard instead of claiming injection.

The production behavior does not add application-specific allowlists beyond the existing terminal-family bundle identifiers and does not log dictated text, selected text, clipboard contents, or AI content.

## Behavior and compatibility

Unchanged behavior:

- Accessibility trust is required before cross-process output delivery.
- The target captured at Fn-down is used; VoiceFlow does not substitute the current frontmost application.
- Terminal-family frontmost output uses Command-V, Control-E, clipboard restoration, and no automatic Enter.
- AX selection replacement attempts to preserve the selected UTF-16 range and place the caret after the inserted text.
- Unicode keyboard events remain a fallback and are posted in 20-character chunks.
- No supported focused text input is delivered through `InjectionCoordinator` as a successful clipboard-copy mode.
- Completion sound and completion-state behavior remain unchanged.

Intentional compatibility improvements:

- Frontmost non-terminal controls that reject AX mutation may now accept normal paste while the prior clipboard is restored.
- The clipboard fallback is never used as a global paste when the captured target is no longer frontmost.
- A non-frontmost captured target may still receive process-targeted keyboard events, but the target application may reject synthetic events while unfocused.

This is a layered best-effort strategy, not a universal guarantee. Browser, Electron, custom, terminal, and editor behavior must be recorded per application and control during manual testing.

## Tests and verification

Completed:

- Focused `TextInjectorTests`: **14 tests, 0 failures**.
- Full `voiceflowTests` XCTest target: **189 tests, 0 failures**; this includes `TextInjectorTests` and `InjectionCoordinatorTests`.
- Clean `./scripts/buildapp.sh --clean`: **BUILD SUCCEEDED**; `build/VoiceFlow.app` was present and ready for manual installation.
- `git diff --check` and staged `git diff --cached --check`: passed.
- `./scripts/verify-change-documentation.sh`: passed with `change-documentation: staged change satisfies the documentation workflow.`

Not run in this environment:

- Manual TextEdit, browser, Electron/editor, terminal-family, target-switch, and clipboard-preservation checks. No manual application compatibility result is claimed by this record.

## Documentation updated

- `specs/spec_04_text_injection.md` now describes the current route order, capability detection, target safety, clipboard behavior, limitations, and acceptance criteria.
- `docs/testing.md` now contains an application-by-application injection matrix covering native controls, browser editors, Electron/code editors, terminal families, target changes, read-only targets, and clipboard safety.

## Feature flags

Not applicable. This change adds no rollout flag, kill switch, remote control, or persisted enable/disable setting. The existing completion-sound preference is unchanged and is not introduced or migrated by this change.

## Migration

Not applicable. The renamed paste abstraction is an internal Swift interface only. No persisted settings, Keychain items, model files, pasteboard formats, serialized data, or user configuration keys change. Historical `spec_changes/028` and `029` retain their original names because they are immutable historical records; current specifications and production references use `TextPasting` and `SystemTextPaster`.

The documentation verifier passed after staging the intended files; it does not alter application behavior.

## Known limitations or follow-up

AX support is determined by the target's exposed attributes and does not guarantee that a control accepts mutation. Clipboard paste requires the captured target to remain frontmost and may be blocked by application behavior or macOS permissions. Process-targeted keyboard events are safer than a global paste after focus changes but may not work while the target is unfocused. Manual verification remains necessary for each browser, Electron/editor, terminal, and custom control that the project chooses to claim as supported.

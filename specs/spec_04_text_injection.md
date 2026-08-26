# SPEC 04 — Accessibility-Safe Text Injection and Output Delivery

## Status and dependency

Specification 04 consumes the final processed text and the application captured when the Fn gesture began. It completes the output side of the VoiceFlow pipeline:

```text
Fn hold → permission/model readiness → record → transcribe/process → output delivery → completed/copied → idle
```

Specification 03 owns transcription and the `onTranscriptionComplete` handoff. `RecordingCoordinator` owns target capture at Fn-down. Specification 04 must use that captured target and must never silently substitute whichever application is frontmost later.

This document is the source of truth for the current implementation. It describes the broad set of macOS text controls that VoiceFlow attempts to support, but it does **not** promise universal compatibility. Actual behavior depends on the target application's Accessibility implementation, paste handling, event acceptance, permissions, and whether the original target remains valid.

## 1. Goals

This stage must:

- Reject empty output and missing or invalid target applications safely.
- Require explicit macOS Accessibility trust before cross-process output delivery.
- Prefer the least invasive supported route for the target control.
- Replace the focused selection when the target exposes a writable Accessibility value and selection range.
- Preserve the existing clipboard whenever VoiceFlow uses temporary clipboard-based paste.
- Support native text fields and areas, search fields, combo boxes, web-backed editable controls that expose suitable Accessibility attributes, and terminal-family applications through their respective routes.
- Fall back conservatively when the preferred route is unavailable, without directing global paste to a different application.
- Copy the final output to the clipboard when no supported focused text input is available.
- Map failures to shared application states and never report success before output delivery completes.
- Play the optional completion sound only after successful injection or clipboard delivery.
- Expose `.completed` or `.copiedToClipboard` long enough for the overlay, then return to `.idle` without overriding a newer interaction or error.
- Keep output text, clipboard contents, audio, and transcription content out of logs.

The overlay, Settings window, model manager, and provider-specific AI processing are consumers of this output contract; none is required for the `TextInjector` unit tests.

## 2. Components and contracts

| Component | Location | Current contract |
|---|---|---|
| `TextInjector` | `voiceflow/Core/Injection/TextInjector.swift` | Validates text, target, and Accessibility trust; detects focused text input; performs AX, paste, or keyboard delivery. |
| `TextInjecting` | Same file | Injectable protocol used by `InjectionCoordinator` and tests. |
| `TextInputAvailabilityChecking` | Same file | Allows the coordinator to decide whether to inject or copy to the clipboard. |
| `FocusedTextSelectionReading` | Same file | Reads selected text for selection-aware AI requests. |
| `KeyboardEventPosting` | Same file | Injectable Unicode CGEvent posting seam. |
| `TextPasting` | Same file | Injectable temporary-clipboard paste seam with optional terminal caret normalization. |
| `SystemTextPaster` | Same file | Snapshots/restores the pasteboard, posts Command-V, and optionally posts Control-E. |
| `SystemClipboardWriter` | Same file | Writes output to the general pasteboard for clipboard delivery. |
| `InjectionCoordinator` | `voiceflow/Core/Injection/InjectionCoordinator.swift` | Decides injection versus clipboard delivery, maps errors, plays success-only sound, and owns completion-state timing. |

`TranscriptionCoordinator.onTranscriptionComplete` provides `(String, NSRunningApplication?)`. The injection coordinator consumes this callback and does not rediscover the frontmost application. A Claude or other provider response is treated like any other final output after provider processing has completed.

## 3. Accessibility permission and captured-target safety

`TextInjector` checks `AXIsProcessTrusted()` before performing any cross-process output operation. If trust is absent, it calls the injected permission requester, whose production implementation invokes `AXIsProcessTrustedWithOptions` with the system prompt option, then throws `.accessibilityPermissionDenied`. The user must explicitly enable VoiceFlow under **System Settings → Privacy & Security → Accessibility**. The injector does not silently bypass this requirement.

The target application is the `NSRunningApplication` captured at Fn-down. A `nil` target or non-positive process identifier throws `.targetApplicationUnavailable`. For operations that send a global Command-V, `TextInjector` separately verifies that the captured target is still the frontmost application by comparing process identifiers through `frontmostApplicationProvider`.

This frontmost check protects against a common race: the user starts recording in one application and changes focus before transcription completes. VoiceFlow never sends a global paste to the new frontmost application. If the original target is no longer frontmost, the global paste route is skipped. A process-targeted keyboard fallback may still be attempted for the captured process; whether that application accepts those events is target-specific.

## 4. Focused text-input detection

`hasTextInput(in:)` is used by `InjectionCoordinator` before it chooses between injection and clipboard delivery. It returns `false` when the target is invalid or Accessibility trust is absent.

Terminal-family applications are treated as supported text-input targets because their shell prompt is not consistently represented as a writable AX text field. For other applications, VoiceFlow obtains the focused AX element and evaluates its capabilities rather than trusting a role alone. It reads the role, enabled state, string `kAXValueAttribute`, settable status for that value, and selected-text range. A control is considered supported when it is not explicitly disabled and exposes either a string value with a positive writability signal or a selected-text range. If settable status is unavailable, a recognized text role with a string value is accepted as a conservative fallback. Recognized roles include `AXTextField`, `AXTextArea`, `AXSearchField`, `AXComboBox`, `AXWebArea`, `AXSecureTextField`, and `AXTokenField` where the other capability signals are present.

An explicit non-settable value is always treated as read-only, even when the role is a text-related role. An element without a string value is not treated as a normal AX-value target. A control that exposes none of these signals is not considered a supported text input by the coordinator. In that case, the final text is copied to the clipboard rather than being sent to an unrelated or unsupported target.

Detection is intentionally capability-based rather than a hard-coded application allowlist. TextEdit, native AppKit text controls, browser editors, Electron/editor controls, and other applications are supported when they expose compatible AX attributes or accept the later fallback route. A particular browser, editor, custom control, secure field, token field, or terminal version may still reject one or more routes. A web page that exposes only a generic `AXWebArea` without editable value/selection signals may still be classified as unsupported; VoiceFlow does not infer editability from the visual appearance of a page.

## 5. Injection route order

After validation and permission checks, `inject(text:into:)` uses this routing policy.

### 5.1 Terminal-family targets

The following bundle identifiers are classified as terminal-family targets:

- `com.apple.Terminal`
- `com.googlecode.iterm2`
- `io.alacritty`
- `com.mitchellh.ghostty`
- `net.kovidgoyal.kitty`
- `org.wezfurlong.wezterm`

If the captured terminal remains frontmost, VoiceFlow uses `SystemTextPaster` with `moveCaretToEndOfLine: true`. The route is:

```text
snapshot clipboard → write temporary output → Command-V → Control-E → restore clipboard
```

Control-E is terminal-only and is not used for ordinary text controls. VoiceFlow does not press Enter. The pasteboard snapshot is restored after the paste and caret command, including when a command fails.

If the captured terminal is no longer frontmost, VoiceFlow skips global paste and proceeds through the non-global fallback sequence. In the final keyboard route, the production poster sends Unicode events to the captured process identifier rather than posting a global paste command.

### 5.2 Standard and web-backed text controls

For a frontmost non-terminal target, VoiceFlow first attempts Accessibility value replacement. It obtains the focused UI element, reads its string AX value, obtains the selected UTF-16 range when available, replaces that range, and attempts to set the caret immediately after the replacement. If no valid selected range is available, the insertion point defaults to the end of the existing value.

If AX value replacement fails, VoiceFlow attempts a normal clipboard paste while the captured target is still frontmost:

```text
snapshot clipboard → write temporary output → Command-V → restore clipboard
```

This route is intended to cover controls such as web-backed editors and custom/native controls that reject direct `kAXValueAttribute` mutation but honor ordinary paste. It has no terminal Control-E step.

If the frontmost paste route fails or is not eligible, VoiceFlow posts Unicode keyboard events to the captured process identifier. The production poster sends text in chunks of 20 Swift characters. This route is not guaranteed to work in every application because some applications reject synthetic events, use custom editors, or require a different input mechanism.

For a non-frontmost non-terminal target, VoiceFlow never sends a global Command-V. It may use the captured process-targeted keyboard fallback after AX failure. This preserves captured-target safety while acknowledging that the target application may not accept events while unfocused.

### 5.3 Retry behavior

If the keyboard poster fails, VoiceFlow makes one additional Accessibility value-replacement attempt. A categorized `TextInjectionError` is propagated if that retry also fails. Failures are logged as method and category metadata only; the output text is never logged.

## 6. Clipboard preservation and no-target delivery

`SystemTextPaster` snapshots all pasteboard item data and restores it after temporary paste. The restore occurs on both the success and error paths. Its normal `paste(text:)` operation does not send Control-E; terminal callers explicitly request `paste(text:moveCaretToEndOfLine: true)`.

`InjectionCoordinator` copies output directly to the general clipboard instead of calling `TextInjector` when:

- There is no captured target application; or
- Accessibility is trusted, a target exists, and `TextInputAvailabilityChecking.hasTextInput(in:)` returns `false`.

This is a successful output mode, represented by `.copiedToClipboard`, and the overlay reports **Copied to Clipboard**. It is not a false text-injection success. The user can paste the result manually with `⌘ + V`.

If a target exists but Accessibility trust is missing, the coordinator does not use the no-input shortcut; it calls `TextInjector`, which requests permission and reports `.accessibilityPermissionDenied`. This preserves the explicit permission contract.

## 7. InjectionCoordinator behavior

`InjectionCoordinator.inject(text:targetApp:)` runs only while `AppStateManager.currentState == .injecting`. Calls in another state are ignored.

On successful injection or clipboard delivery, it:

1. Logs content-free output metadata.
2. Reads the persisted `playCompletionSound` setting, defaulting to `false`.
3. If enabled, reads `completionSoundEffect`, uses `.tink` for invalid values, and plays the selected native `NSSound` effect at subtle volume.
4. Transitions to `.completed` after injection or `.copiedToClipboard` after clipboard delivery.
5. Waits approximately 400 ms.
6. Returns to `.idle` only if the state is still the same completion state; a newer interaction or error wins.

Available persisted sound values are `Tink`, `Pop`, and `Glass`. The sound is never played for empty output, transcription failure, permission denial, target failure, injection failure, or clipboard-write failure.

| Output result | Shared application state |
|---|---|
| Successful text injection | `.completed`, then `.idle` |
| Successful no-target/no-input clipboard copy | `.copiedToClipboard`, then `.idle` |
| Missing Accessibility permission | `.error(.accessibilityPermissionDenied)` |
| Empty text, invalid target, AX failure, paste failure, keyboard failure, or clipboard failure | `.error(.injectionFailed)` |

## 8. Core pipeline wiring

The application composition connects the stages with main-actor tasks:

```text
RecordingCoordinator.onRecordingComplete
  → TranscriptionCoordinator.transcribe(audioURL:targetApp:)
  → TranscriptionCoordinator.onTranscriptionComplete
  → InjectionCoordinator.inject(text:targetApp:)
```

The output stage participates in the state sequence:

```text
preparingModel → recording → processing → injecting → completed/copiedToClipboard → idle
```

The overlay may render `.injecting` as “Processing…”, `.completed` as “Done!”, and `.copiedToClipboard` as “Copied to Clipboard”. Presentation wording must not change the underlying delivery or safety rules.

## 9. Privacy, logging, and permissions

The injection implementation may log process identifier, target bundle identifier, permission status, selected route, character count, and error category. It must not log dictated text, selected text, AI prompts or responses, audio data, or clipboard contents. Temporary clipboard data is held only for the paste operation and then the prior pasteboard items are restored.

Microphone permission is owned by the recording stage. Accessibility permission is required for this output stage. Input Monitoring or related system approval may also be required by macOS for synthetic keyboard events or global monitoring. Missing permissions must lead to actionable UI guidance and a recoverable idle/error state.

## 10. Automated testing requirements

| Test file | Required coverage |
|---|---|
| `voiceflowTests/Injection/TextInjectorTests.swift` | Terminal-family classification; frontmost-only clipboard fallback; terminal end-of-line intent; non-frontmost terminal process-targeted fallback; clipboard restoration; AX selection/caret helpers; empty/nil target handling; permission denial; keyboard fallback/error behavior. |
| `voiceflowTests/Injection/InjectionCoordinatorTests.swift` | Injecting-state gate; injection success; clipboard delivery; completion states; sound selection; no sound on failures; generic and Accessibility-specific error mapping. |
| `voiceflowTests/Transcription/TranscriptionPipelineIntegrationTests.swift` | Final processed text and captured target reaching the injection callback. |

Unit tests must inject permission checkers/requesters, target bundle/frontmost providers, keyboard posters, text pasters, text injectors, clipboard writers, and sound players. They must not post real keyboard events or write real dictated content to logs.

The automated suite cannot prove that every application accepts AX mutation, Command-V, or synthetic Unicode events. Application-specific behavior requires manual verification with disposable text and no sensitive data.

## 11. Manual verification matrix

Use a fresh unsigned or Debug build, grant the required permissions, and use the same build throughout the session. Use a disposable phrase such as “The quick brown fox jumps over the lazy dog.”

| Scenario | Procedure | Expected result |
|---|---|---|
| Native field | Focus TextEdit or another native editable field, optionally select text, then dictate. | AX replacement reaches the selected range or caret, the caret is after the inserted text, and the prior clipboard remains intact. |
| Browser editor | Test a disposable `contenteditable` or textarea in Safari, Chrome, or Firefox. | If AX mutation is rejected, a frontmost paste fallback may deliver the text; the clipboard is restored. Record the exact browser/editor result rather than generalizing it to all web apps. |
| Electron/editor control | Test a disposable editable control in an Electron or code editor application. | AX, frontmost paste, or keyboard fallback may succeed depending on the control; no other application receives a global paste. Record unsupported cases. |
| Terminal-family | Focus Terminal, iTerm2, Alacritty, Ghostty, Kitty, or WezTerm; preserve a harmless clipboard value; dictate a short command without pressing Enter. | Frontmost terminal paste inserts the output, Control-E places the caret at line end, no Enter is sent, and the previous clipboard is restored. |
| Captured target changes | Start in one application, hold Fn, switch applications or close the target before output completes. | The new frontmost application does not receive global Command-V. The original process-targeted fallback may be attempted or the operation may report an error. |
| Read-only/no input | Focus a read-only control or leave no supported text input active. | The coordinator copies the final text to the clipboard and shows **Copied to Clipboard**, or reports a clipboard error; it does not claim text was injected. |
| Missing permission | Revoke Accessibility permission and repeat. | VoiceFlow requests/guides permission, reports an Accessibility error, and does not claim success. |
| Completion | Enable the completion sound and repeat successful injection and clipboard delivery. | The selected Tink, Pop, or Glass sound plays only after successful output; `.completed` or `.copiedToClipboard` is visible briefly before idle. |

## 12. Acceptance criteria

- Empty output is rejected before AX, pasteboard, or keyboard operations.
- A `nil` or invalid target is rejected without guessing a replacement application.
- Accessibility trust is required and the system permission request is used when trust is absent.
- The target captured at Fn-down is used; the current frontmost application is never substituted.
- Terminal-family frontmost targets use temporary Command-V plus Control-E, restore the clipboard, and never receive automatic Enter.
- Standard and web-backed targets use AX value replacement first, then frontmost-only clipboard paste, then captured-process Unicode keyboard events when appropriate.
- Non-frontmost targets never receive a global paste command.
- AX selection replacement preserves the intended UTF-16 range and attempts to place the caret after the inserted text.
- Normal non-terminal paste never posts Control-E.
- No supported focused text input results in clipboard delivery, not false injection success.
- Clipboard contents are restored after temporary paste, including paste errors.
- Output failures map to `.error(.injectionFailed)`, except missing Accessibility trust, which maps to `.error(.accessibilityPermissionDenied)`.
- Successful injection and clipboard delivery produce their corresponding completion state and return to idle after approximately 400 ms unless superseded.
- Completion sound is disabled by default and plays only after successful output.
- Automated injection tests pass, and any manual application claims are limited to applications actually tested.
- Audio, spoken text, selected text, AI prompts/responses, injected text, and clipboard contents never appear in logs.

## 13. Known limitations and inconsistency register

AX behavior varies across macOS applications. Some controls expose a role but reject value mutation; some expose no usable AX value; some accept paste but reject synthetic keyboard events; and some custom editors do not expose enough state to support selection replacement. VoiceFlow therefore uses capability checks and layered fallbacks rather than claiming universal injection.

A process-targeted keyboard event is safer than a global paste when the original target is no longer frontmost, but the target application may ignore events while unfocused. If a target closes or its process identifier becomes invalid, no replacement target is selected and output may be reported as an error or copied only when the coordinator had already classified the target as unsupported.

The historical terminal-only abstraction was generalized to `TextPasting`/`SystemTextPaster` so the same clipboard-preserving mechanism can be used for a frontmost non-terminal fallback. Historical `spec_changes/028` and `029` retain their original names as historical records; they are not current API references.

## Handoff to Specification 05

Specification 05 may observe `AppStateManager`, `AudioRecorder.audioLevel`, `.completed`, and `.copiedToClipboard`. It must not change the Accessibility permission gate, captured-target rule, output route order, clipboard restoration, terminal Control-E behavior, no-Enter rule, or success-only completion sound contract.

## References

[1]: ../voiceflow/Core/Injection/TextInjector.swift "VoiceFlow text injector"
[2]: ../voiceflow/Core/Injection/InjectionCoordinator.swift "VoiceFlow injection coordinator"
[3]: ../voiceflow/Core/Transcription/TranscriptionCoordinator.swift "VoiceFlow transcription callback"
[4]: ../voiceflowTests/Injection/TextInjectorTests.swift "Text injector tests"
[5]: ../voiceflowTests/Injection/InjectionCoordinatorTests.swift "Injection coordinator tests"
[6]: ../voiceflowTests/Transcription/TranscriptionPipelineIntegrationTests.swift "Transcription pipeline integration tests"
[7]: https://developer.apple.com/documentation/applicationservices/axisprocesstrusted "Apple Accessibility trust API"
[8]: ../voiceflow/Core/LLM/ClaudeClient.swift "Claude BYOK client and command processor"

## Completion gate

Specification 04 is complete for this change when the focused injection tests, the broader suite, and a clean build pass. Manual application compatibility must be reported per tested application and must not be inferred from unit tests alone.

## Implementation inconsistency register

The historical specification described keyboard events as the primary method and implied that Accessibility permission was optional. The current implementation intentionally uses an explicit Accessibility gate, AX value replacement, a frontmost-only clipboard-paste compatibility fallback, and a captured-process keyboard fallback. This intentional difference must not be removed to restore the historical behavior.

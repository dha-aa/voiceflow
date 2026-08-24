# SPEC 04 — Accessibility-Safe Text Injection and Core Pipeline Completion

## Status and dependency

Specification 04 consumes the final processed text—either locally normalized text or the response from an explicitly requested Claude command—and the captured target application from Specification 03, then completes the core VoiceFlow pipeline. The current pipeline is:

```text
Fn hold → permission/model readiness → record → process → transcribe → inject → completed → idle
```

This document is the source of truth for the actual text injection and completion behavior. It does not describe a generic “type anywhere without permission” implementation: the current application requires Accessibility trust before injection begins because it first uses the macOS Accessibility API and only then falls back to keyboard events.

## 1. Goals

This stage must:

- Reject empty text and missing/invalid target applications safely.
- Require and request macOS Accessibility permission before cross-process injection.
- Insert text into the focused element of the application captured at Fn-down.
- Preserve and replace the selected range where the target Accessibility API supports it.
- Fall back to Unicode keyboard events when the Accessibility value-update path fails.
- Map injection failures to user-visible shared errors.
- Play an optional short completion sound only after successful injection.
- Expose the explicit `.completed` state for the overlay and menu bar.
- Return to `.idle` after approximately 400 ms while remaining safe if a new state arrives first.
- Prove the full core pipeline without depending on the overlay or Settings UI.

The overlay, Settings window, and model-management UI are later presentation layers. They must not be required for the core injection gate to pass.

## 2. Components and contracts

| Component | Location | Current contract |
|---|---|---|
| `TextInjector` | `voiceflow/Core/Injection/TextInjector.swift` | Validates target/text/permission and performs AX or keyboard injection |
| `TextInjecting` | Same file | Injectable protocol used by tests and `InjectionCoordinator` |
| `KeyboardEventPosting` | Same file | Injectable keyboard-event seam |
| `InjectionCoordinator` | `voiceflow/Core/Injection/InjectionCoordinator.swift` | State gate, injection call, completion sound, `.completed` timing, and error mapping |
| `CompletionSoundEffect` | Same file | `tink`, `pop`, and `glass` selectable effects |
| `CompletionSoundPlaying` | Same file | Injectable completion-sound seam |

`TranscriptionCoordinator.onTranscriptionComplete` provides:

```swift
(String, NSRunningApplication?)
```

The injection coordinator consumes that callback and does not rediscover the frontmost application. It treats a Claude-generated response the same as locally processed text; provider routing is complete before this handoff. Target capture remains the responsibility of `RecordingCoordinator`.

## 3. TextInjector behavior

`TextInjector` validates the input in this order:

1. Empty text throws `.emptyText`.
2. A `nil` target or invalid process identifier throws `.targetApplicationUnavailable`.
3. Accessibility trust is checked with `AXIsProcessTrusted()`.
4. If trust is missing, the injector invokes its permission requester, which uses `AXIsProcessTrustedWithOptions` with the system prompt option, then throws `.accessibilityPermissionDenied`.

The user must enable VoiceFlow under **System Settings → Privacy & Security → Accessibility**. The injector does not guess a replacement target and does not silently discard text.

When trusted, the injector first attempts the Accessibility path. It creates an application AX element for the target process, reads `kAXFocusedUIElementAttribute`, reads the focused element’s `kAXValueAttribute`, obtains `kAXSelectedTextRangeAttribute` when available, and replaces the selected range with the provided text. If a selected range is unavailable, it uses a caret at the end of the existing value. After updating the value, it attempts to restore the caret immediately after the inserted text.

If the Accessibility path fails despite trust, the injector falls back to `KeyboardEventPosting`. The production poster creates Unicode `CGEvent` key-down/key-up pairs and posts text in chunks of 20 Swift characters to the target process identifier. If keyboard posting fails, it makes one additional Accessibility attempt and propagates a categorized injection failure if that also fails.

The current injector logs only process ID, target bundle identifier, permission status, method, and error category. It never logs the text being inserted.

### Architectural note

The historical specification described keyboard events as the primary method and implied that Accessibility permission was optional. That is not the current behavior. Accessibility trust is required up front; AX value replacement is primary, and keyboard events are a fallback for a trusted target when AX update fails. This difference is intentional and must not be “fixed” by silently bypassing the permission gate.

## 4. InjectionCoordinator behavior

`InjectionCoordinator.inject(text:targetApp:)` runs only when `AppStateManager.currentState == .injecting`. Calls in any other state are ignored and do not invoke the injector.

On successful injection, the coordinator:

1. Logs content-free success metadata.
2. Reads `playCompletionSound` from `UserDefaults`, defaulting to `false`.
3. If enabled, reads `completionSoundEffect`, defaults invalid values to `.tink`, and plays the selected native `NSSound` effect at a subtle volume.
4. Transitions to `.completed`.
5. Waits approximately 400 ms.
6. Transitions to `.idle` only if the state is still `.completed`; a newer interaction or error wins.

The available persisted sound values are `Tink`, `Pop`, and `Glass`. The sound is never played when transcription fails, text is empty, permission is denied, the target is unavailable, or injection fails.

Injection errors map as follows:

| Injector result | Shared application state |
|---|---|
| `.accessibilityPermissionDenied` | `.error(.accessibilityPermissionDenied)` |
| `.emptyText`, missing target, AX failure, keyboard failure, other errors | `.error(.injectionFailed)` |

The shared state manager later recovers errors to `.idle` after its normal two-second delay.

## 5. Full core pipeline wiring

The AppDelegate retains the coordinators and connects them with main-actor tasks:

```text
RecordingCoordinator.onRecordingComplete
  → TranscriptionCoordinator.transcribe(audioURL:targetApp:)
  → TranscriptionCoordinator.onTranscriptionComplete
  → InjectionCoordinator.inject(text:targetApp:)
```

The core stages own these state transitions:

```text
preparingModel → recording → processing → injecting → completed → idle
```

The overlay may later render `.injecting` as “Processing…” and `.completed` as “Done!”, but this stage must be tested independently of that UI.

## 6. Testing requirements

The current executable tests are:

| Test file | Required coverage |
|---|---|
| `voiceflowTests/Injection/TextInjectorTests.swift` | Full keyboard poster forwarding, empty text rejection, nil target rejection, Accessibility permission prompt/denial, and poster failure propagation |
| `voiceflowTests/Injection/InjectionCoordinatorTests.swift` | Injecting-state gate, success state sequence, selected completion sound, no sound on failures, generic failure, and accessibility-specific error |
| `voiceflowTests/Transcription/TranscriptionPipelineIntegrationTests.swift` | Processed text reaching the injection callback from the transcription coordinator |

Unit tests must use injected permission checkers/requesters, keyboard posters, text injectors, and completion-sound players. They must not post real keyboard events or write real dictated content to logs.

The core integration verification should use a controlled WAV fixture, a test session factory, a test injector, and a test target where possible. A real TextEdit verification is a manual test because it depends on macOS Accessibility permission and the user’s focused application.

Manual verification:

1. Grant VoiceFlow microphone and Accessibility permissions.
2. Focus a TextEdit document or another known editable field.
3. Hold Fn, speak a short sentence, and release Fn.
4. Confirm the text appears in the original focused field without manual paste.
5. Confirm the state sequence reaches `.processing`, `.injecting`, `.completed`, and then `.idle`.
6. Enable the completion sound and repeat; confirm one subtle sound plays only after text appears.
7. Disable Accessibility and repeat; confirm the app requests permission and reports an accessibility error without claiming success.
8. Repeat with a missing or closed target and confirm no alternate application receives text.

## 7. Acceptance criteria

- Empty text is rejected before any event or AX operation.
- `nil` and invalid target applications are rejected without target guessing.
- Accessibility trust is required before injection and a system permission prompt is requested when absent.
- The captured target application is used; the current frontmost application is not substituted later.
- Trusted targets use AX focused-element value replacement first.
- AX injection preserves selection replacement and attempts to restore the caret.
- Trusted AX failure falls back to Unicode keyboard events in 20-character chunks.
- Injection failures map to `.error(.injectionFailed)`, except missing Accessibility trust maps to `.error(.accessibilityPermissionDenied)`.
- Successful injection transitions to `.completed` and then `.idle` after approximately 400 ms, unless a newer state supersedes it.
- Completion sound is disabled by default, uses Tink/Pop/Glass, and plays only after successful injection.
- The core pipeline works without the overlay or Settings window.
- All injection and core-pipeline tests pass.
- Audio, spoken text, transcribed text, Claude prompts/responses, and injected text never appear in logs.

## 8. Core Pipeline Verification Gate

Specification 04 is complete only when a controlled test and a real manual TextEdit test prove:

```text
Fn held → audio captured → transcription processed → target text injected → completed → idle
```

The user must not need to copy/paste manually, and an injection failure must be visible as an error rather than a false completion. Only after this gate passes should Specification 05 add visual feedback.

## 9. Handoff to Specification 05

Specification 05 may observe `AppStateManager`, `AudioRecorder.audioLevel`, and the injection completion states. It must not change the core coordinator sequencing, permission gate, target capture, or success-only completion sound behavior.

## References

[1]: ../voiceflow/Core/Injection/TextInjector.swift "VoiceFlow text injector"
[2]: ../voiceflow/Core/Injection/InjectionCoordinator.swift "VoiceFlow injection coordinator"
[3]: ../voiceflow/Core/Transcription/TranscriptionCoordinator.swift "VoiceFlow transcription callback"
[4]: ../voiceflowTests/Injection/TextInjectorTests.swift "Text injector tests"
[5]: ../voiceflowTests/Injection/InjectionCoordinatorTests.swift "Injection coordinator tests"
[6]: ../voiceflowTests/Transcription/TranscriptionPipelineIntegrationTests.swift "Transcription pipeline integration tests"
[7]: https://developer.apple.com/documentation/applicationservices/axisprocesstrusted "Apple Accessibility trust API"
[8]: ../voiceflow/Core/LLM/ClaudeClient.swift "Claude BYOK client and command processor"

## Implementation inconsistency register

The old specification required direct return to `.idle` and omitted the `.completed` state and completion sound. The current implementation intentionally inserts `.completed` for about 400 ms and supports optional Tink/Pop/Glass feedback. The old keyboard-first, permission-optional approach is also superseded by the current Accessibility-first, permission-required implementation.

## Completion gate

Do not begin Specification 05 until unit tests pass, a controlled end-to-end test reaches the injection callback, and real TextEdit verification confirms that Accessibility-safe injection works without stealing or changing the target focus unexpectedly.

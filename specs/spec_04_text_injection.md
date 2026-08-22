# SPEC 04 — Text Injection & End-to-End Core Pipeline

## 1. Purpose

This specification builds the final stage of the core pipeline: text injection. When transcription completes, the processed text must be automatically inserted into whatever application and text field the user was focused on before holding `Fn`.

This is also the specification that completes and verifies the entire core pipeline end-to-end:

```
Fn held → Audio capture → Fn released → Transcription → Text injection → Idle
```

By the end of this spec, the full VoiceFlow workflow works without any UI. A developer can hold `Fn`, speak, release it, and see the transcribed text appear in a text editor — all without touching the overlay or settings window.

This is the **Core Pipeline Verification Gate**. The UI is not started until this gate passes.

---

## 2. Scope

- Implement `TextInjector` to insert text into the currently focused macOS text field using macOS Accessibility APIs.
- Connect `TextInjector` to `TranscriptionCoordinator.onTranscriptionComplete`.
- Drive `AppStateManager` to `.idle` after successful injection or to `.error(.injectionFailed)` on failure.
- Request Accessibility permission and handle denial gracefully.
- Write unit and integration tests for the injection pipeline.
- Run the complete end-to-end core pipeline test: `Fn hold → record → transcribe → inject → idle`.
- Verify the complete pipeline works WITHOUT any UI beyond the menu bar icon.

---

## 3. Out of Scope

Do NOT implement any of the following in this specification:

- The recording overlay window (Spec 05).
- Settings window or model management UI (Spec 06).
- Audio recording or transcription changes (Spec 02 and Spec 03 are complete).
- Clipboard-based fallback injection (unless Accessibility API approach fails entirely — document if needed).

---

## 4. Dependencies

**Specs 01, 02, and 03 must be complete and verified before starting this spec.**

Required from Spec 01:
- `AppState` — `.injecting`, `.idle`, `.error` cases.
- `AppStateManager.transition(to:)`.

Required from Spec 03:
- `TranscriptionCoordinator.onTranscriptionComplete: ((String, NSRunningApplication?) -> Void)?` — stable interface.
- `AppStateManager` is in `.injecting` state when injection should begin.

**Framework dependencies:**
- `ApplicationServices` / `AXUIElement` — macOS Accessibility API for text injection.
- No new Swift Package dependencies.

**Required system permission:**
- Accessibility permission: `System Settings → Privacy & Security → Accessibility → VoiceFlow: ON`.
- The app must request this permission and provide a clear explanation to the user.

---

## 5. Implementation Requirements

### 5.1 Text Injector

Implement `TextInjector` in `Core/Injection/TextInjector.swift`.

#### How macOS text injection works

The standard, application-compatible approach uses `CGEvent` keyboard simulation:

1. Before recording starts (when `Fn` is pressed), save a reference to the currently focused application using `NSWorkspace.shared.frontmostApplication`.
2. After transcription, simulate keyboard events to type the text into the saved focused element.

The two available approaches:

**Approach A: CGEvent key simulation (recommended)**
- Simulate keyboard `keyDown` / `keyUp` events using `CGEvent(keyboardEventSource:virtualKey:keyDown:)`.
- Set the Unicode string on the event using `CGEventKeyboardSetUnicodeString`.
- Post events to the saved application using `CGEventPostToPid`.
- This does not require the Accessibility API and works with most applications.

**Approach B: AXUIElement setValue**
- Get the focused UI element using `AXUIElementCreateApplication(targetApp.processIdentifier)` + `kAXFocusedUIElementAttribute`. Do NOT use `AXUIElementCreateSystemWide()`.
- Get its current value: `AXUIElementCopyAttributeValue`.
- Append the transcription and set it back: `AXUIElementSetAttributeValue` with `kAXValueAttribute`.
- Requires Accessibility permission.
- Does not work in all apps (e.g., web browsers may reject it).

**Recommended implementation:**
Use Approach A (`CGEvent`) as the primary method. It works across more applications without requiring Accessibility permission. If it fails, fall back to Approach B. Document the approach used.

> **Important:** The focused application is captured by `RecordingCoordinator` (Spec 02) and threaded through `TranscriptionCoordinator` (Spec 03) to arrive here. Spec 04 must simply consume this passed target application.

```swift
final class TextInjector {

    // Check if accessibility permission is granted (needed for fallback Approach B)
    var isAccessibilityPermissionGranted: Bool {
        AXIsProcessTrusted()
    }

    // Inject text into the application that was focused before recording
    func inject(text: String, into targetApp: NSRunningApplication?) throws { ... }
}
```

Error handling:
- If `targetApp` is `nil` → Do not guess or discover another application. Throw an error so `InjectionCoordinator` can transition state to `.error(.injectionFailed)`.
- If `CGEvent` posting fails → throw / call `AppStateManager.transition(to: .error(.injectionFailed))`.
- Spec 04 consumes the valid transcription result produced by Spec 03. Empty transcription is handled by Spec 03 and must not be silently converted into successful completion by the injection stage.

### 5.2 Injection Coordinator

Implement `InjectionCoordinator` in `Core/Injection/InjectionCoordinator.swift`.

```swift
final class InjectionCoordinator {
    init(stateManager: AppStateManager, injector: TextInjector) { ... }

    // Connected to TranscriptionCoordinator.onTranscriptionComplete
    func inject(text: String, targetApp: NSRunningApplication?) async { ... }
}
```

Internal logic:
1. Receive `text` and `targetApp`.
2. State should already be `.injecting` (set by Spec 03).
3. Call `injector.inject(text:into:)`.
4. On success: `stateManager.transition(to: .idle)`.
5. On failure: `stateManager.transition(to: .error(.injectionFailed))`.

### 5.3 Full Pipeline Wiring

At the app entry point, wire the final coordinator. The interfaces established by Spec 02 and Spec 03 are frozen. Spec 04 must consume these interfaces without modifying them.

```swift
transcriptionCoordinator.onTranscriptionComplete = { [weak injectionCoordinator] text, targetApp in
    Task {
        await injectionCoordinator?.inject(text: text, targetApp: targetApp)
    }
}
```

---

## 6. Files and Components

### Files to create

| File | Purpose |
|------|---------|
| `Core/Injection/TextInjector.swift` | CGEvent-based text injection into focused app |
| `Core/Injection/InjectionCoordinator.swift` | Wires injection + state transitions |

### Files that may be modified

| File | Permitted change |
|------|----------------|
| `App/VoiceFlowApp.swift` | Wire up `InjectionCoordinator` |
| `App/AppDelegate.swift` | Same |

### Files that must NOT be modified

| File | Reason |
|------|--------|
| `Core/State/AppState.swift` | Stable from Spec 01 |
| `Core/State/AppStateManager.swift` | Stable from Spec 01 |
| `Core/Audio/FnKeyMonitor.swift` | Stable from Spec 02 |
| `Core/Audio/AudioRecorder.swift` | Stable from Spec 02 |
| `Core/Audio/RecordingCoordinator.swift` | Stable from Spec 02 |
| `Core/Transcription/TranscriptionEngine.swift` | Stable from Spec 03 |
| `Core/Transcription/TextProcessor.swift` | Stable from Spec 03 |
| `Core/Transcription/ModelManager.swift` | Stable from Spec 03 |
| `Core/Transcription/TranscriptionCoordinator.swift` | Stable from Spec 03 |

### Reserved (do not create yet)

- `UI/Overlay/` — Spec 05
- `UI/Settings/` — Spec 06

---

## 7. Tests

### Unit Tests: `TextInjectorTests.swift`

```
test_textInjector_injectsText_intoFocusedApp
  Open a test text field (e.g., a test window with NSTextField).
  Call inject(text: "hello world", into: testApp).
  Assert the text field now contains "hello world".
  (This may need to run as a UI test or with Accessibility permission granted.)

test_textInjector_rejects_emptyText
  Call inject(text: "", into: testApp).
  // Note: While Spec 03 handles empty strings, if TextInjector receives one, it should arguably throw an error, or just do nothing. But the pipeline test below verifies the actual flow.

test_endToEnd_corePipeline_emptyTranscription
  1. Feed an audio file containing only silence (or trigger a mock transcription returning "").
  2. Assert AppStateManager.currentState transitions to .error(.noAudioDetected).
  3. Assert no successful injection occurs.
  4. Assert state recovers to .idle via normal error recovery.

test_textInjector_reportsError_onFailure
  Simulate a failure condition (e.g., invalid app reference).
  Assert injectionFailed error or state transition is triggered.

test_textInjector_handlesNilTargetApp
  Call inject(text: "hello", into: nil).
  Assert injection does not occur, no target is guessed, and injectionFailed error is thrown.
```

### Integration Test: Full End-to-End Core Pipeline

> This is the **Core Pipeline Verification Test**. It must pass before Spec 05 begins.

```
test_endToEnd_corePipeline_noUI
  Prerequisites:
  - A downloaded WhisperKit model (tiny.en for speed).
  - A pre-recorded test audio file: 16,000 Hz mono WAV with phrase "hello pipeline test".
  - A visible text field (e.g., Notes.app or a test window) in focus.
  - Accessibility permission granted.

  Steps:
  1. Put a text editor in focus.
  2. Simulate Fn key down (call onFnKeyDown directly on FnKeyMonitor).
  3. Assert AppStateManager.currentState == .recording.
  4. Feed the test audio file to RecordingCoordinator.onRecordingComplete.
  5. Wait for transcription to complete.
  6. Assert AppStateManager.currentState transitioned through .processing → .injecting → .idle.
  7. Assert the text editor now contains transcribed text resembling "hello pipeline test".
```

### Manual End-to-End Verification

> This must be done on real hardware with a real microphone.

```
Full push-to-talk test:
1. Open TextEdit or Notes.
2. Click in the text area to focus it.
3. Switch to VoiceFlow (or keep it in the menu bar).
4. Hold Fn. Speak "the quick brown fox". Release Fn.
5. Watch console for: recording → processing → injecting → idle.
6. Confirm "the quick brown fox" (or a close approximation) appears in TextEdit.
7. No crash. No hang. No manual copy-paste required.

Error case:
1. Open VoiceFlow without granting Accessibility permission.
2. Hold Fn. Speak. Release.
3. Confirm state goes to .error(.injectionFailed) or appropriate error.
4. Confirm the error is logged clearly.
```

---

## 8. Acceptance Criteria

All of the following must be true before this spec is complete:

- [ ] `TextInjector` successfully injects text into a focused macOS text field.
- [ ] Text injection does not require the user to click or paste manually.
- [ ] Empty transcription is correctly rejected by the pipeline with an error (handled by Spec 03), and never silently skips injection.
- [ ] The focused application is correctly captured at `Fn` key down.
- [ ] After injection, `AppStateManager` returns to `.idle`.
- [ ] Injection failure transitions state to `.error(.injectionFailed)`.
- [ ] Unit tests for `TextInjector` pass.
- [ ] End-to-end core pipeline integration test passes (programmatic audio → transcription → injection).
- [ ] Manual push-to-talk test: hold Fn, speak, release, text appears in focused app — without any overlay UI.

### ✅ Core Pipeline Verification Gate

The complete core pipeline is proven working when:

1. A user can hold `Fn`, speak a sentence, release `Fn`, and see the transcribed text appear in any focused text field.
2. The state machine follows: `idle → recording → processing → injecting → idle`.
3. This works without the recording overlay or any settings UI.
4. It is reproducible and consistent across multiple attempts.

**Only after this gate passes may Spec 05 begin.**

---

## 9. Completion Gate

**This spec is NOT complete until:**

1. All acceptance criteria are checked off.
2. All unit tests pass.
3. End-to-end core pipeline integration test passes.
4. Manual push-to-talk test works reliably on real hardware.
5. The **Core Pipeline Verification Gate** is passed and documented.
6. No known errors or pipeline failures remain.

**Do not proceed to Spec 05 until this gate passes.**

---

## 10. Handoff to Spec 05

Spec 05 receives a fully working, tested core pipeline. The UI is now a client of this already-proven system.

| Component | What Spec 05 can rely on |
|-----------|--------------------------|
| Full pipeline | `Fn held → record → transcribe → inject → idle` works without UI |
| `AppStateManager` | All state transitions verified and stable |
| `AppState` | Stable enum — Spec 05 observes it to drive overlay states |
| `AudioRecorder.audioLevel` | Published float (0.0–1.0) for waveform visualization |
| `RecordingCoordinator` | Stable Fn key detection and audio capture |
| `TranscriptionCoordinator.onTranscriptionComplete` | Stable interface |

Spec 05 will add the recording overlay window that observes `AppStateManager` and `AudioRecorder.audioLevel`. It must not break or change any core pipeline components.

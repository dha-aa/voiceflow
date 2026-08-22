# SPEC 02 — Audio Recording & Fn Key Detection

## 1. Purpose

This specification builds the audio capture engine and the global `Fn` key monitor — the two core input mechanisms of VoiceFlow.

When the user holds `Fn`, audio capture starts. When the user releases `Fn`, audio capture stops. The captured audio buffer is prepared and handed to the next stage (Spec 03: Transcription).

This stage proves that the push-to-talk interaction model works independently of any UI. By the end of this spec, holding `Fn` starts recording, releasing it stops recording, and the captured audio is a valid in-memory buffer ready for transcription — all testable without any overlay or UI.

---

## 2. Scope

- Implement a `FnKeyMonitor` that detects `Fn` press-and-hold and release using a global `CGEvent` tap or `NSEvent` global monitor.
- Implement an `AudioRecorder` that captures microphone audio into a PCM buffer or temporary audio file.
- Request microphone permission on first use and handle denial gracefully.
- Drive `AppStateManager` state transitions:
  - `Fn` held → `transition(to: .recording)`
  - `Fn` released → `transition(to: .processing)`
  - Error (mic denied, etc.) → `transition(to: .error(...))`
- Expose the captured audio buffer via a stable interface that Spec 03 consumes.
- Write unit and integration tests for the recording pipeline.

---

## 3. Out of Scope

Do NOT implement any of the following in this specification:

- WhisperKit model loading or transcription (Spec 03).
- Text injection (Spec 04).
- The recording overlay UI (Spec 05).
- Settings window (Spec 06).
- Model management or downloading.
- Audio-level metering for UI visualization (Spec 05 will consume audio levels from the recorder, but do not build the UI).
- Any waveform or visual feedback.

You MAY expose an audio level publisher (e.g., `@Published var audioLevel: Float`) from `AudioRecorder` so Spec 05 can observe it — but do not render anything with it in this spec.

---

## 4. Dependencies

**Spec 01 must be complete and verified before starting this spec.**

Required from Spec 01:
- `AppState` enum — `.idle`, `.recording`, `.processing`, `.error` cases.
- `AppStateManager` — `transition(to:)` method.
- `Info.plist` — `NSMicrophoneUsageDescription` already set.
- Hardened Runtime entitlement — `com.apple.security.device.audio-input = YES` already set.
- `Core/Audio/` directory exists.

**Framework dependencies:**
- `AVFoundation` — microphone capture.
- `CoreGraphics` / `AppKit` — `CGEvent` tap or `NSEvent` global monitor for `Fn` key detection.
- No new Swift Package dependencies needed.

**Assumptions:**
- The microphone permission description and entitlement were correctly set in Spec 01.
- `AppStateManager` is injected and available.

---

## 5. Implementation Requirements

### 5.1 Fn Key Monitor

Implement `FnKeyMonitor` in `Core/Audio/FnKeyMonitor.swift`.

The `Fn` key is a system-level key on Apple keyboards. Detection approach:
- Use `NSEvent.addGlobalMonitorForEvents(matching:)` with `.flagsChanged` to detect modifier key changes.
- Check for the `.function` flag in `NSEvent.modifierFlags` to identify the `Fn` key specifically.
- A single tap must NOT trigger recording — only a sustained hold should start recording.

> **Implementation note on Fn detection:**  
> `NSEvent` global monitors for `.flagsChanged` can detect `Fn` on Apple Silicon and Intel Macs via the `.function` modifier flag. If this approach proves unreliable in testing, fall back to a `CGEvent` tap with `kCGEventFlagsChanged`. Document whichever approach is used and why.

The `FnKeyMonitor` must:
- Emit a `fnKeyDown` event when `Fn` is first pressed.
- Emit a `fnKeyUp` event when `Fn` is released.
- Call a closure or delegate method for each event.
- Handle edge cases: `Fn` held while state is NOT `.idle` (ignore second hold to prevent task races and audio overwrite), `Fn` released before audio starts (abort gracefully).

```swift
final class FnKeyMonitor {
    var onFnKeyDown: (() -> Void)?
    var onFnKeyUp: (() -> Void)?

    func start() { ... }
    func stop() { ... }
}
```

### 5.2 Audio Recorder

Implement `AudioRecorder` in `Core/Audio/AudioRecorder.swift`.

Responsibilities:
- Request microphone permission using `AVAudioApplication.requestRecordPermission` (macOS 14) or `AVCaptureDevice.requestAccess(for: .audio)`.
- Start capturing microphone audio when `startRecording()` is called.
- Stop capturing and return the recorded audio when `stopRecording()` is called.
- Handle microphone permission denial by calling `AppStateManager.transition(to: .error(.microphoneUnavailable))`.

Audio format:
- Sample rate: 16,000 Hz (required by WhisperKit).
- Channels: 1 (mono).
- Format: PCM float32.

Output:
- The recorded audio is saved to a temporary file (`FileManager.default.temporaryDirectory`) or held in memory as a buffer.
- The output type must be `URL` (path to a `.wav` or `.m4a` file) or `AVAudioPCMBuffer`, whichever integrates more cleanly with WhisperKit's `transcribe(audioPath:)` or `transcribe(audioPCMBuffer:)` API.

Audio level metering:
- Expose `var audioLevel: Float` (value between 0.0 and 1.0) updated continuously during recording.
- This property will be observed by the UI in Spec 05 to drive the waveform visualizer.

```swift
@Observable
final class AudioRecorder {
    private(set) var audioLevel: Float = 0.0
    private(set) var isRecording: Bool = false

    func requestPermission() async -> Bool { ... }
    func startRecording() throws { ... }
    func stopRecording() -> URL? { ... }   // returns path to recorded audio file
}
```

### 5.3 Recording Coordinator

Implement `RecordingCoordinator` in `Core/Audio/RecordingCoordinator.swift`.

This class wires `FnKeyMonitor` and `AudioRecorder` together and drives `AppStateManager`.

```swift
final class RecordingCoordinator {
    init(stateManager: AppStateManager, recorder: AudioRecorder, keyMonitor: FnKeyMonitor) { ... }

    func start() { ... }   // begin monitoring for Fn key
    func stop() { ... }    // stop monitoring

    // Expose the completed audio URL and the target application for Spec 03 to consume
    var onRecordingComplete: ((URL, NSRunningApplication?) -> Void)?
}
```

Internal logic:
1. `FnKeyMonitor.onFnKeyDown` fires → **Check if `stateManager.currentState == .idle`.** 
   - If YES: save `NSWorkspace.shared.frontmostApplication` → call `AudioRecorder.startRecording()` → call `stateManager.transition(to: .recording)`.
   - If NO: explicitly ignore the input (do not start a new recording, do not overwrite the buffer).
2. `FnKeyMonitor.onFnKeyUp` fires → If currently `.recording`, call `AudioRecorder.stopRecording()` → call `stateManager.transition(to: .processing)` → call `onRecordingComplete(audioURL, savedApplication)`.
3. Any error → call `stateManager.transition(to: .error(...))`.

---

## 6. Files and Components

### Files to create

| File | Purpose |
|------|---------|
| `Core/Audio/FnKeyMonitor.swift` | Global `Fn` key press/release detection |
| `Core/Audio/AudioRecorder.swift` | Microphone capture, audio level metering |
| `Core/Audio/RecordingCoordinator.swift` | Wires key monitor + recorder + state transitions |

### Files that may be modified

| File | Permitted change |
|------|----------------|
| `App/VoiceFlowApp.swift` | Instantiate `RecordingCoordinator` and call `.start()` |
| `App/AppDelegate.swift` | Same — start coordinator on app launch |

### Files that must NOT be modified

| File | Reason |
|------|--------|
| `Core/State/AppState.swift` | Stable interface from Spec 01 |
| `Core/State/AppStateManager.swift` | Stable interface from Spec 01 |
| `UI/MenuBar/MenuBarController.swift` | UI is not touched in this spec |

### Reserved (do not create yet)

- `Core/Transcription/` — Spec 03
- `Core/Injection/` — Spec 04
- `UI/Overlay/` — Spec 05
- `UI/Settings/` — Spec 06

---

## 7. Tests

Write and run these tests before marking this spec complete.

### Unit Tests: `FnKeyMonitorTests.swift`

```
test_fnKeyMonitor_callsOnKeyDown_whenFnPressed
  Simulate a flagsChanged event with .function flag set.
  Assert onFnKeyDown closure is called.

test_fnKeyMonitor_callsOnKeyUp_whenFnReleased
  Simulate a flagsChanged event with .function flag cleared.
  Assert onFnKeyUp closure is called.

test_fnKeyMonitor_doesNotFire_onSingleTapWithoutHold
  (If debounce/hold-detection logic is implemented)
  Simulate a very short key press (< threshold). Assert no recording started.
```

### Unit Tests: `AudioRecorderTests.swift`

```
test_audioRecorder_initialState_notRecording
  Create AudioRecorder. Assert isRecording == false.

test_audioRecorder_startRecording_setsIsRecording
  Call startRecording(). Assert isRecording == true.
  (Mock AVAudioEngine or use a test audio session.)

test_audioRecorder_stopRecording_setsIsRecordingFalse
  Start, then stop. Assert isRecording == false.

test_audioRecorder_stopRecording_returnsNonNilURL
  Start, record briefly, stop. Assert returned URL is not nil.
  Assert the file exists at the returned URL.

test_audioRecorder_audioLevel_updatesWhileRecording
  Start recording. Wait briefly. Assert audioLevel > 0.0.
  (May require a real device test or a mocked audio input.)
```

### Unit Tests: `RecordingCoordinatorTests.swift`

```
test_coordinator_transitionsToRecording_onFnDown
  Trigger onFnKeyDown. Assert AppStateManager.currentState == .recording.

test_coordinator_transitionsToProcessing_onFnUp
  Trigger onFnKeyDown, then onFnKeyUp.
  Assert AppStateManager.currentState == .processing.

test_coordinator_callsOnRecordingComplete_withAudioURL
  Trigger full Fn-down → Fn-up cycle.
  Assert onRecordingComplete is called with a non-nil URL.
```

### Integration Test: Full Recording Pipeline

```
test_fullRecordingPipeline
  1. Start RecordingCoordinator.
  2. Simulate Fn key down.
  3. Assert state == .recording.
  4. Wait 1 second.
  5. Simulate Fn key up.
  6. Assert state == .processing.
  7. Assert onRecordingComplete is called with a valid audio file URL.
  8. Assert audio file exists and has non-zero size.
```

### Manual Verification

```
- Build and run the app.
- Hold Fn. Confirm terminal/console logs show: "State → recording".
- Speak a few words.
- Release Fn. Confirm console shows: "State → processing", then "Recording complete: <path>".
- Open the audio file at the logged path in QuickTime Player. Confirm your voice is audible.
- Deny microphone permission in System Settings. Relaunch. Hold Fn.
  Confirm console shows: "State → error(microphoneUnavailable)".
```

---

## 8. Acceptance Criteria

All of the following must be true before this spec is complete:

- [ ] `FnKeyMonitor` detects `Fn` press and release on the test machine.
- [ ] Holding `Fn` transitions `AppStateManager` to `.recording`.
- [ ] Releasing `Fn` transitions `AppStateManager` to `.processing`.
- [ ] `AudioRecorder` captures audio at 16,000 Hz, mono, PCM format.
- [ ] `stopRecording()` returns a valid `URL` pointing to a non-empty audio file.
- [ ] The recorded audio file is playable and contains recognizable speech.
- [ ] Microphone permission denial transitions state to `.error(.microphoneUnavailable)`.
- [ ] `audioLevel` updates continuously while recording (verified via logs).
- [ ] All unit tests pass.
- [ ] Integration test passes.
- [ ] Menu bar icon updates: shows `mic.fill` during `.recording`, `waveform` during `.processing`.

---

## 9. Completion Gate

**This spec is NOT complete until:**

1. All acceptance criteria are checked off.
2. All unit tests and the integration test pass.
3. Manual verification confirms real microphone audio is captured and the file is playable.
4. The `RecordingCoordinator.onRecordingComplete` interface is stable and ready for Spec 03 to consume.
5. `Fn` key detection works reliably on the target hardware.

**Do not proceed to Spec 03 until this gate passes.**

---

## 10. Handoff to Spec 03

Spec 03 receives these stable, verified components:

| Component | What Spec 03 can rely on |
|-----------|--------------------------|
| `RecordingCoordinator.onRecordingComplete` | Called with a valid `URL` and the target `NSRunningApplication?` after every recording session |
| `AudioRecorder.stopRecording()` | Returns a `URL` to a PCM audio file at 16,000 Hz mono |
| `AppStateManager` | In `.processing` state when transcription should begin |
| Audio file format | 16,000 Hz, mono, PCM — WhisperKit-compatible |

Spec 03 will connect to `RecordingCoordinator.onRecordingComplete` and pass the audio URL to WhisperKit for transcription, threading the target application through.

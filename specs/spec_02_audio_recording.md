# SPEC 02 — Fn Push-to-Talk and Local Audio Recording

## Status and dependency

Specification 02 extends the foundation from Specification 01. It defines the current input and audio boundary consumed by Specifications 03–07. The implementation is deliberately local: microphone samples are written to a temporary WAV file and are never sent to a remote service or written to logs.

The current interaction is **sustained push-to-talk**, not a toggle. A short `Fn` tap is ignored. A hold emits one key-down event after the hold threshold, starts the recording flow, and a release emits one key-up event that stops recording and hands a temporary audio URL to the transcription stage. [1] [2]

## 1. Goals

This stage provides a reliable global Fn monitor, microphone permission handling, 16 kHz mono PCM recording, normalized audio-level metering, and the `RecordingCoordinator` handoff to transcription. It must preserve the application that was focused when the sustained Fn hold began.

This stage does not perform WhisperKit loading or transcription, text injection, overlay rendering, Settings, or model downloading. Those later stages consume the interfaces documented here.

## 2. Components and contracts

| Component | Location | Current responsibility |
|---|---|---|
| `FnKeyMonitor` | `voiceflow/Core/Audio/FnKeyMonitor.swift` | Global `.flagsChanged` monitoring through `NSEvent.addGlobalMonitorForEvents` |
| `AudioRecorder` | `voiceflow/Core/Audio/AudioRecorder.swift` | AVAudioEngine input capture, conversion, temporary WAV output, and audio metering |
| `AudioRecording` | Same file | Testable recorder abstraction used by `RecordingCoordinator` |
| `RecordingCoordinator` | `voiceflow/Core/Audio/RecordingCoordinator.swift` | Coordinates Fn events, permission, model readiness, recording, target-app capture, and callbacks |
| `ModelReadinessChecking` | Same file | Optional async gate implemented by `TranscriptionEngine` |

`RecordingCoordinator.onRecordingComplete` has the stable signature:

```swift
var onRecordingComplete: ((URL, NSRunningApplication?) -> Void)?
```

The callback receives a real temporary audio URL and the application that was frontmost at the beginning of the sustained hold. The target may be `nil`; later injection must reject that case rather than guessing a target.

## 3. Fn monitoring

`FnKeyMonitor` installs a global flags-changed monitor when `start()` is called and removes it in `stop()`. It checks `event.modifierFlags.contains(.function)` and does not use a key-code toggle.

The default hold threshold is **0.25 seconds**. On a transition from not pressed to pressed, the monitor schedules a delayed key-down callback. If Fn is released before the threshold, the work item is cancelled and neither callback fires. If the threshold elapses while Fn remains pressed, `onFnKeyDown` fires exactly once. A corresponding release then fires `onFnKeyUp` once. Repeated pressed events while already pressed are ignored.

The test seam `handleFlagsChangedForTesting(isPressed:)` exercises the same state machine without synthesizing system events. The production monitor does not itself decide whether the application is idle; `RecordingCoordinator` performs that guard.

```swift
final class FnKeyMonitor {
    var onFnKeyDown: (() -> Void)?
    var onFnKeyUp: (() -> Void)?

    init(holdThreshold: TimeInterval = 0.25)
    func start()
    func stop()
    func handleFlagsChangedForTesting(isPressed: Bool)
}
```

## 4. Audio recording

`AudioRecorder` uses `AVAudioEngine` and an input-node tap. It requests microphone permission using `AVCaptureDevice.requestAccess(for: .audio)` through its injectable `permissionRequester` closure. The recorder does not begin engine startup until its permission result is granted.

The output format is created as non-interleaved PCM float32 at 16,000 Hz and one channel. The input format is obtained from the microphone input node. If necessary, `AVAudioConverter` converts each input buffer to the target format. The recorder writes converted buffers to a unique file named `recording_<UUID>.wav` in `FileManager.default.temporaryDirectory`.

`startRecording()` is idempotent when already recording. It creates the target format, input engine, converter, WAV file, input tap, and running engine. Setup failures remove the tap, release the engine/file references, remove the incomplete output file, and throw a recorder error.

`stopRecording()` stops the engine, removes the tap, releases the file and engine, resets `isRecording` and `audioLevel`, and returns the recorded URL. If no active recording exists, it returns `nil`. It records only metadata such as an opaque audio identifier, duration, buffer count, frame count, byte count, and write-error count. It never logs samples or spoken content.

`audioLevel` is an observable normalized RMS-derived value clamped to `0...1`; the recorder updates it from converted buffers. The overlay later samples this value at 30 Hz. The recorder does not implement a maximum duration or silence classifier. Silence is mapped to `noAudioDetected` by the transcription stage when no usable text is produced.

## 5. RecordingCoordinator sequencing

The coordinator is main-actor isolated and installs weak callback closures on the key monitor. It must be constructed with the shared `AppStateManager`, an `AudioRecording`, the `FnKeyMonitor`, and optionally a `ModelReadinessChecking` implementation.

The production sequence is:

```text
Fn pressed
  → FnKeyMonitor waits 250 ms
  → RecordingCoordinator confirms state == idle
  → capture NSWorkspace.shared.frontmostApplication
  → request microphone permission
  → if a readiness checker exists: state = preparingModel and await readiness
  → if Fn is still held: start AudioRecorder
  → state = recording

Fn released after recording starts
  → stop AudioRecorder
  → if URL is nil: state = error(noAudioDetected)
  → otherwise state = processing
  → onRecordingComplete(URL, capturedTargetApplication)
```

The coordinator ignores Fn-down when the shared state is not `.idle` or when a hold is already active. It does not overwrite the prior target application or audio session. If the user releases Fn while permission or model readiness is pending, the startup task is cancelled, no recording completion callback is sent, and the state returns or remains `.idle`; this is normal cancellation rather than a microphone error.

Before recording begins, the optional readiness checker is called after permission is granted. The coordinator shows `.preparingModel` while waiting. Readiness failure maps to `.error(.modelFailedToLoad)`. A recorder permission denial or startup failure maps to `.error(.microphoneUnavailable)`. The central `AppStateManager` later recovers error states to `.idle`.

`stop()` stops monitoring, cancels pending startup, clears the held state and target application, and stops an active recorder if needed. It is safe to call during shutdown.

## 6. Implementation requirements

The implementation must preserve these rules:

1. All microphone access and audio processing remain local.
2. The default Fn hold threshold remains 0.25 seconds unless a deliberate product change is specified.
3. A tap shorter than the threshold must not start recording.
4. The target application is captured at sustained Fn key-down, before recording startup can change focus.
5. Recording cannot begin until permission is granted and, in production, the selected model is ready.
6. An early release cancels pending startup without emitting a false transcription callback.
7. Audio is written in a WhisperKit-compatible 16 kHz, mono, PCM float32 WAV format.
8. Test doubles must be injectable through `AudioEngineProviding`, `AudioRecording`, and the permission closure.
9. Logs may contain only privacy-safe metadata; never audio, speech, transcript, or full file contents.

## 7. Tests and verification

The current executable tests are:

| Test file | Required coverage |
|---|---|
| `voiceflowTests/Audio/FnKeyMonitorTests.swift` | Delayed key-down, release callback, short-tap suppression, duplicate-down suppression |
| `voiceflowTests/Audio/RecordingCoordinatorTests.swift` | Readiness wait, preparing state, recording start, processing transition, callback URL, non-idle rejection, early-release cancellation, permission/start errors |
| `voiceflowTests/Audio/RecordingPipelineIntegrationTests.swift` | Full simulated Fn cycle, synthetic audio emission, non-empty output file, 16 kHz sample rate, mono channel count |

The local test command is:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project voiceflow.xcodeproj \
  -scheme voiceflow \
  -configuration Debug \
  -destination 'platform=macOS' \
  ONLY_ACTIVE_ARCH=YES \
  -only-testing:voiceflowTests \
  test CODE_SIGNING_ALLOWED=NO
```

Manual verification on real hardware must confirm that a short Fn tap does nothing, holding Fn eventually shows the recording flow, microphone denial produces a microphone error, releasing before model readiness does not create a recording, and a sustained hold produces a temporary WAV that later reaches `.processing`. Do not inspect or distribute real recordings as part of automated CI.

## 8. Acceptance criteria

- `FnKeyMonitor` uses the global `.flagsChanged` monitor and the `.function` modifier.
- The default hold threshold is 250 ms and short taps produce no callbacks.
- A sustained hold produces exactly one down callback and one release callback.
- Permission is requested before microphone engine startup.
- Permission denial maps to `.error(.microphoneUnavailable)`.
- The recorder writes temporary 16 kHz mono PCM float32 WAV data and resets cleanly after stopping.
- The recorder exposes a normalized `audioLevel` between 0 and 1.
- `RecordingCoordinator` captures the frontmost application on sustained hold.
- Recording waits for `ModelReadinessChecking` when the production engine is supplied.
- The pre-recording state is `.preparingModel`, not `.recording`, while readiness is pending.
- Early release cancels startup without calling `onRecordingComplete`.
- Successful release transitions to `.processing` and invokes `onRecordingComplete` with the audio URL and captured target.
- All audio-stage tests pass.
- No audio or speech content appears in logs.

## 9. Handoff to Specification 03

Specification 03 receives a temporary WAV URL in the target format, the captured `NSRunningApplication?`, and a state already set to `.processing`. It must not reimplement Fn monitoring or microphone capture. It must add model resolution/readiness and transcription while preserving the early-release and target-capture contracts.

## References

[1]: ../voiceflow/Core/Audio/FnKeyMonitor.swift "Fn key monitor implementation"
[2]: ../voiceflow/Core/Audio/AudioRecorder.swift "Audio recorder implementation"
[3]: ../voiceflow/Core/Audio/RecordingCoordinator.swift "Recording coordinator implementation"
[4]: ../voiceflow/Core/State/AppState.swift "Shared application states and errors"
[5]: ../voiceflowTests/Audio/FnKeyMonitorTests.swift "Fn monitor tests"
[6]: ../voiceflowTests/Audio/RecordingCoordinatorTests.swift "Recording coordinator tests"
[7]: ../voiceflowTests/Audio/RecordingPipelineIntegrationTests.swift "Audio pipeline integration test"

## Implementation inconsistency register

The historical specification assumed that Fn-down immediately entered `.recording`, but the current production flow correctly waits for microphone permission and selected-model readiness and exposes `.preparingModel`. It also assumed that a recording object itself would classify silence; the current implementation leaves silence/no-text classification to transcription. No maximum recording duration is currently implemented. These are documented current behaviors, not hidden requirements.

## Completion gate

Do not begin Specification 03 until the Fn monitor, recorder, coordinator readiness/cancellation behavior, and audio-format integration test pass. The gate proves the audio boundary; it does not require a WhisperKit model or real transcription yet.

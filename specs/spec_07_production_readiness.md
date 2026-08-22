# SPEC 07 — Final Testing, Polish & Production Readiness

## 1. Purpose

This specification completes VoiceFlow. All core functionality and UI are implemented and verified. This stage focuses on making the application production-ready: hardening edge cases, improving error handling and user-facing messages, ensuring performance, verifying accessibility, and preparing the app for code signing and distribution.

No new features are added in this specification.

---

## 2. Scope

- Complete edge case handling across all components.
- Audit and improve all error messages and user-facing error states.
- Performance profiling: startup time, recording latency, transcription time, injection speed.
- Memory management audit: no leaks, no retain cycles.
- macOS Accessibility audit: VoiceOver labels, keyboard navigation in Settings.
- Code signing and entitlements review.
- App Store / notarization preparation (if distributing outside direct install).
- Final end-to-end test suite across multiple real usage scenarios.
- Code review and cleanup: remove debug print statements, add documentation comments to public interfaces.

---

## 3. Out of Scope

Do NOT add any new features in this specification:

- No new UI surfaces.
- No new transcription modes.
- No new keyboard shortcuts.
- No integration with external APIs.

If a new feature is discovered to be needed, it must be planned as a separate specification after Spec 07.

---

## 4. Dependencies

**Specs 01–06 must be complete and verified before starting this spec.**

The full application must be working end-to-end with all of the following verified:
- Core pipeline: `Fn hold → record → transcribe → inject → idle`.
- Recording overlay with waveform and animations.
- Settings window with model management.
- Menu bar popover with live model status.

---

## 5. Implementation Requirements

### 5.1 Edge Case Hardening

Audit and fix all known edge cases. At minimum, handle the following:

**Recording edge cases:**
- [ ] `Fn` is held, recording starts, then `Fn` is accidentally released and immediately re-pressed within 200ms. Define behavior: ignore brief releases, or treat as a new recording session.
- [ ] Recording starts but no audio is captured (mic level stays at 0.0 for the entire session). Transition to `.error(.noAudioDetected)` with a clear user message.
- [ ] Recording session longer than 60 seconds. Define maximum recording duration and cut off gracefully. Show a brief "max duration reached" message.
- [ ] Another application captures the microphone exclusively (e.g., a video call). Handle the AVAudioEngine error gracefully.

**Transcription edge cases:**
- [ ] WhisperKit model is deleted from disk between sessions (was present at launch, deleted externally). Detect on next transcription attempt and show `.error(.modelNotInstalled)`.
- [ ] The system is under heavy memory pressure and WhisperKit initialization fails. Retry once, then show a clear error.
- [ ] Transcription returns a string containing only whitespace or punctuation. Treat as no audio detected.

**Injection edge cases:**
- [ ] The focused application closes between `Fn` press and injection. Handle gracefully — do not crash.
- [ ] The focused field is read-only (e.g., a label, browser URL bar in some states). Attempt injection; if it fails, fall back to clipboard + notification.
- [ ] Injection into a terminal emulator (e.g., Terminal.app, iTerm). Verify CGEvent approach works. Document known limitations.

**Model management edge cases:**
- [ ] Download interrupted mid-way (network failure, app quit). Verify partial download is cleaned up and does not leave a corrupt model on disk.
- [ ] Attempting to delete the model currently loaded in `TranscriptionEngine`. Unload first, delete, prompt user to select another.
- [ ] Disk full during model download. Handle the error and show a clear message.

### 5.2 Error Message Audit

Review every `AppError` case and ensure:
- Every error has a human-readable description accessible from the UI.
- Every error causes the correct overlay error state to appear.
- No error silently fails without the user knowing.

Define `var localizedDescription: String` on `AppError`:

```swift
extension AppError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .microphoneUnavailable:
            return "Microphone is not available. Check System Settings → Privacy → Microphone."
        case .noAudioDetected:
            return "No audio was detected. Please speak clearly while holding Fn."
        case .modelNotInstalled:
            return "No WhisperKit model is installed. Open Settings → Models to download one."
        case .modelFailedToLoad:
            return "Failed to load the selected model. Try restarting VoiceFlow."
        case .transcriptionFailed:
            return "Transcription failed. Please try again."
        case .injectionFailed:
            return "Could not insert text. Grant Accessibility permission in System Settings."
        }
    }
}
```

Update `RecordingOverlayView` error state to show `AppError.localizedDescription` instead of a generic "Error" string.

### 5.3 Performance Profiling

Measure and document the following timing benchmarks on the target hardware:

| Metric | Acceptable Target |
|--------|-------------------|
| App launch to menu bar icon visible | < 1.5 seconds |
| `Fn` press to recording overlay appears | < 200ms |
| `Fn` release to processing state | < 100ms |
| Transcription of 5-second audio (tiny model) | < 3 seconds |
| Transcription of 5-second audio (large-v3) | < 8 seconds |
| Text injection after transcription | < 100ms |
| Overlay disappears after injection | ~400ms (by design) |

Use Instruments (Time Profiler) to identify any unexpected hot paths. Fix any bottleneck that pushes beyond the acceptable targets.

Profile memory usage during a full recording session. Verify WhisperKit resources are released when not in use (not held indefinitely).

### 5.4 Memory Leak Audit

- Run the application with the Leaks instrument in Xcode.
- Ensure no retain cycles exist between `RecordingCoordinator`, `TranscriptionCoordinator`, `InjectionCoordinator`, and `AppStateManager`.
- All closures captured by coordinators must use `[weak self]` where appropriate.
- Verify that `AudioRecorder` audio buffers are released after transcription.
- Verify that `TranscriptionEngine`'s WhisperKit instance is held as a weak reference or released appropriately when the model is changed.

### 5.5 Accessibility Audit

- All interactive controls in the Settings window have VoiceOver labels.
- Model rows have descriptive accessibility labels (e.g., "Whisper Large V3, 626 megabytes, downloaded, active").
- Download and Delete buttons have clear accessibility hints.
- Toggle controls have accessibility values ("on" / "off").
- The Settings window is fully navigable with keyboard (Tab, Space, Return).

Use Xcode Accessibility Inspector to audit the Settings window. Document any known VoiceOver limitations in the overlay (the overlay is transient and does not need to be VoiceOver-accessible by design).

### 5.6 Code Quality Cleanup

- Remove all debug `print()` statements. Replace with `os.Logger` calls at appropriate levels (`.debug`, `.info`, `.error`).
- Add documentation comments (`///`) to all public interfaces:
  - `AppStateManager.transition(to:)`
  - `AudioRecorder.startRecording()` / `stopRecording()`
  - `TranscriptionEngine.transcribe(audioURL:)`
  - `TextInjector.inject(text:into:)`
  - `ModelManager.downloadModel(id:)`
- Ensure all files have a header comment with filename and brief description.
- Remove any commented-out dead code.

### 5.7 Code Signing & Entitlements

Verify the final entitlements file contains exactly:

```xml
<key>com.apple.security.app-sandbox</key>
<false/>
<key>com.apple.security.device.audio-input</key>
<true/>
```

> **Note:** App Sandbox must be OFF for VoiceFlow because:
> - Global `CGEvent` taps for Fn key detection require non-sandboxed access.
> - Text injection via `CGEvent` posting to other processes requires non-sandboxed access.
> - Accessibility API access requires non-sandboxed access.

If targeting Mac App Store distribution, revisit the sandboxing requirement — it may require using only allowed entitlements or changing the injection approach.

Review and confirm:
- [ ] Hardened Runtime is enabled.
- [ ] Microphone entitlement is present.
- [ ] Code signing identity is configured for the target distribution method (Developer ID or App Store).
- [ ] Notarization is completed if distributing outside the App Store.

### 5.8 Info.plist Final Audit

Verify `Info.plist` is complete:

| Key | Value |
|-----|-------|
| `LSUIElement` | `YES` |
| `NSMicrophoneUsageDescription` | Clear user-facing string |
| `CFBundleName` | `VoiceFlow` |
| `CFBundleIdentifier` | `com.yourname.voiceflow` (or appropriate) |
| `CFBundleShortVersionString` | Release version (e.g., `1.0.0`) |
| `CFBundleVersion` | Build number |
| `NSHumanReadableCopyright` | Copyright string |

---

## 6. Files and Components

### Files that may be modified

Any file in the project may be modified for bug fixes, edge case handling, code quality, and documentation.

However, architectural changes to existing interfaces are NOT allowed unless a genuine defect requires it. If an architectural change is needed, document it explicitly before making it.

### Do not add new features

Do not add new files that implement new functionality. Refactoring existing files is fine.

---

## 7. Tests

### Final End-to-End Test Suite

Run the complete manual test suite on real hardware:

```
Scenario 1: Basic push-to-talk
  Target: TextEdit
  Input: "The quick brown fox jumps over the lazy dog"
  Expected: Text appears in TextEdit accurately within acceptable timing.

Scenario 2: Short utterance
  Target: Notes.app
  Input: "Hello" (< 1 second)
  Expected: "Hello" (or "hello") is injected. No noAudioDetected error.

Scenario 3: Long utterance
  Target: VS Code
  Input: ~45 seconds of speech (paragraph of text)
  Expected: Full transcription injected or graceful max-duration cutoff.

Scenario 4: Silence (no speech)
  Target: Any text field
  Input: Hold Fn for 3 seconds without speaking.
  Expected: noAudioDetected error shown in overlay. No crash. Returns to idle.

Scenario 5: Multiple rapid sessions
  Target: TextEdit
  Input: Hold Fn 5 times in quick succession (< 1 second apart).
  Expected: Each session is handled cleanly. No crashes. No state corruption.

Scenario 6: Model switch during use
  1. Switch model in Settings.
  2. Immediately hold Fn and speak.
  Expected: Transcription uses the new model (or handles loading gracefully).

Scenario 7: Microphone revoked
  1. During the session, revoke microphone in System Settings.
  2. Hold Fn.
  Expected: microphoneUnavailable error shown. No crash.

Scenario 8: Accessibility revoked
  1. During the session, revoke Accessibility in System Settings.
  2. Complete a recording session.
  Expected: injectionFailed error shown. No crash. Text is NOT silently lost.
```

### Regression Test

Re-run all unit tests from Specs 01–06 and confirm all pass.

---

## 8. Acceptance Criteria

All of the following must be true before this spec is complete:

- [ ] All 8 end-to-end scenarios pass without crashes.
- [ ] Performance benchmarks meet the targets in §5.3.
- [ ] No memory leaks detected by Instruments.
- [ ] All `AppError` cases display correct, actionable user messages.
- [ ] Settings window is fully keyboard-navigable.
- [ ] All VoiceOver labels are in place.
- [ ] All debug `print()` statements replaced with `os.Logger`.
- [ ] Public interfaces have documentation comments.
- [ ] Code is signed with a valid Developer ID or App Store certificate.
- [ ] If distributing outside the App Store: app is notarized and passes `spctl` check.
- [ ] `Info.plist` audit passes.
- [ ] All unit tests from Specs 01–06 still pass.
- [ ] No known crashes or state machine corruptions.

---

## 9. Completion Gate

**VoiceFlow is DONE when:**

1. All acceptance criteria above are checked off.
2. All end-to-end scenarios pass on real hardware.
3. Performance benchmarks are within targets.
4. No known bugs or crashes remain.
5. The application is code-signed and ready for distribution.

---

## 10. Handoff

The completed VoiceFlow application is handed off to production. It delivers:

**User experience:**
> Hold `Fn` → Speak → Release `Fn` → Transcribed text appears in the focused application.

**Architecture summary:**

```
FnKeyMonitor
    ↓
AudioRecorder ──── audioLevel ────→ WaveformView (UI)
    ↓
RecordingCoordinator
    ↓
TranscriptionEngine (WhisperKit)
    ↓
TextProcessor
    ↓
TranscriptionCoordinator
    ↓
TextInjector (CGEvent)
    ↓
AppStateManager ──── currentState ──→ OverlayWindowController (UI)
                                   → MenuBarController (UI)
```

**Component ownership:**

| Spec | What was built |
|------|---------------|
| 01 | App skeleton, state machine, menu bar |
| 02 | Fn key detection, microphone capture |
| 03 | WhisperKit transcription, model management, text cleanup |
| 04 | Text injection, end-to-end core pipeline |
| 05 | Recording overlay, waveform, animations |
| 06 | Settings window, model management UI |
| 07 | Production hardening, edge cases, distribution |

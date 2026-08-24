# Specification Change 013 — Parakeet TDT v3 Local Speech Engine

## Summary

VoiceFlow now has a second local speech-to-text engine in addition to WhisperKit: Parakeet TDT 0.6B v3 through FluidAudio 0.15.6 and the official Core ML model repository `FluidInference/parakeet-tdt-0.6b-v3-coreml`.

The implementation is intentionally separate from WhisperKit. It adds a shared `SpeechTranscriptionEngine` contract and `SpeechTranscriptionRouter`, while preserving the existing WhisperKit `TranscriptionEngine`, model catalog, custom-model import, preload behavior, and downstream text-processing/AI/injection flow.

## Implemented changes

- Added `SpeechTranscriptionEngine` with common preparation, readiness, preload, selection-change, and audio-file transcription operations.
- Added `SpeechRecognitionSettings` with persisted `WhisperKit` and `Parakeet TDT v3` engine choices.
- Added `SpeechTranscriptionRouter`, which dispatches to the selected engine and forwards model-selection changes.
- Refactored `TranscriptionCoordinator` and application composition to use the shared engine boundary.
- Added `ParakeetModelManager` with an app-owned FluidAudio model directory, Apple Silicon/platform detection, structural artifact validation, download progress, cancellation, and installed-state refresh.
- Added `ParakeetTranscriptionEngine` with cached FluidAudio session loading, readiness gating, fresh per-utterance decoder state, local batch transcription, and shared error mapping.
- Added engine selection and Parakeet status/download controls to Settings while retaining the WhisperKit model UI.
- Pinned FluidAudio at `v0.15.6` in the Xcode project and package lockfile.
- Added deterministic Parakeet session, error, persistence, and router tests. The verified suite contains 137 XCTest methods with zero failures.

## Behavioral boundary

Parakeet v3 operates on VoiceFlow’s finalized local audio file. The current model path is batch transcription, not live streaming. FluidAudio streaming APIs and their separate models are not enabled by this change. No microphone audio is sent to FluidAudio’s servers or any other remote speech service.

The implementation supports model reuse and preloading. The model is not considered ready until the local model manager reports a valid installation and the FluidAudio session has loaded. A missing model, unsupported Intel host, invalid artifact, or loading/runtime failure is surfaced through the existing recoverable transcription error path. WhisperKit is never silently substituted for a selected Parakeet engine.

Claude/OpenAI AI processing is unchanged. After either local engine returns text, VoiceFlow applies the existing TextProcessor, selection-aware Claude command route, Grammar Fix precedence, and Accessibility injection behavior.

## Privacy and distribution notes

Normal recording, temporary audio, model files, and inference remain local. Structured logs contain only metadata such as engine/model identifiers, paths, durations, character counts, and error categories; they do not contain audio, transcripts, prompts, responses, or inserted text. Parakeet weights are not bundled into the app and must be downloaded or otherwise installed by the user through the model-management flow.

The Parakeet v3 path requires Apple Silicon for the supported Core ML configuration. The app remains non-sandboxed because the existing global Fn monitoring and cross-process Accessibility injection require that architecture. This change does not add Screen Recording permission or screen capture.

## Verification

Automated verification covers the shared contract, engine persistence, router dispatch, readiness preconditions, session reuse, model-load failure mapping, and runtime transcription failure mapping with fake providers. The app target builds successfully unsigned with FluidAudio linked. Real Parakeet recognition quality, model download integrity on a user network, Apple Silicon performance, and TextEdit replacement must still be verified manually with the official model and a disposable document.

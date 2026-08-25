# Specification Change 023 — Reliable Model Readiness After Download

## Summary

This change fixes the first-use model loading issue where a newly downloaded model could be valid and already loaded during download validation, but then be discarded when the model became active. It also hardens FluidAudio preload handling so repeated availability callbacks do not cancel or duplicate a load for the same Parakeet variant.

## Root cause

WhisperKit download validation can call `TranscriptionEngine.validateModelLoad(...)` and successfully create a usable session before the model is selected. When that same model was subsequently selected, `preloadSelectedModel()` unconditionally cancelled load state, cleared the cached session, and started a second load. This made a newly downloaded model appear not ready even though validation had already completed, and created unnecessary first-use latency.

FluidAudio had the equivalent lifecycle risk: `preloadSelectedModel()` cancelled existing work and cleared its cache on every availability callback. Because model download, selection, refresh, and engine callbacks can arrive close together, repeated callbacks could restart an otherwise valid or in-flight load.

## WhisperKit behavior

`TranscriptionEngine.preloadSelectedModel()` now checks the selected model before cancelling state. If the exact selected model already has a cached validated session, it preserves that session and reports a readiness-preserving skip. If the exact selected model is already loading, it preserves the in-flight task so `waitUntilReady()` can join it. Stale work is still cancelled when the selected model changes.

The existing `session()` path remains the single source of truth for model readiness. `waitUntilReady()` awaits the cached or in-flight session, and `transcribe(audioURL:)` uses that same session. The recording coordinator therefore continues to wait in `.preparingModel` before recording starts, and transcription cannot proceed against an unready model.

## FluidAudio behavior

`ParakeetTranscriptionEngine` now tracks the variant associated with its in-flight load. A repeated availability callback for the same selected, cached variant preserves the ready session. A repeated callback for the same variant while loading preserves the in-flight task. If the selected variant changes, stale work is cancelled and a load for the new variant is started. The engine’s `session()` method will not join an in-flight session belonging to a different variant.

## User-visible workflow

The expected lifecycle is:

> Model downloaded → structural validation → engine load validation → ready session retained → model selected/availability callback → existing ready session reused → Fn readiness wait succeeds → recording/transcription uses the ready model.

For a slow newly downloaded model, the application remains in its existing preparation/readiness flow until the load completes. The first transcription joins the in-flight load rather than starting a duplicate load. If loading fails, the existing model-load error path remains in effect and no invalid model is reported as ready.

## Privacy and compatibility

The fix does not change local speech recognition, the WhisperKit or FluidAudio providers, model directory rules, download validation, selected-model persistence, recording behavior, text injection, or AI processing. Diagnostics identify model IDs, variants, readiness transitions, and timing only; audio and transcription text are not logged.

## Acceptance criteria

| Area | Acceptance criterion |
|---|---|
| Newly downloaded WhisperKit model | A session successfully created during download validation remains cached when that model becomes active. |
| WhisperKit first use | Selecting a validated model does not trigger a duplicate load; `waitUntilReady()` and transcription reuse the ready session. |
| Slow load | A first-use readiness wait joins an existing in-flight load rather than cancelling and restarting it. |
| FluidAudio availability | Repeated availability/preload callbacks for the same Parakeet variant reuse a ready or in-flight session. |
| Variant changes | A selection change cannot join a session loading a different Parakeet variant. |
| Failure handling | Existing model-not-installed and model-load-failed errors remain unchanged. |
| Validation | Unchanged baseline completed with **164 tests and zero failures**. The new red regression reproduced the WhisperKit reload issue and the FluidAudio repeated-preload issue. Focused engine coverage completed with **23 tests and zero failures**. The final full suite completed with **166 tests and zero failures**. |

## Verification note

The test suite uses injected session factories and temporary valid model fixtures. It verifies lifecycle and session identity deterministically without downloading large model weights or claiming hardware inference validation.

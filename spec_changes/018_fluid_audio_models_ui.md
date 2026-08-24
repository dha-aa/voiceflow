# Specification Change 018 — FluidAudio Models UI

## Summary

This change reorganizes the Models pane around speech-engine providers. The first picker now presents **WhisperKit** and **FluidAudio**. When FluidAudio is selected, the secondary picker is labeled **FluidAudio model** and presents the available Parakeet TDT v2 and v3 model variants with their download and validation state.

## User-facing behavior

The UI no longer presents `Parakeet TDT v3` as if it were the speech engine. Parakeet v2/v3 are models supplied by the FluidAudio engine. An incomplete or stale FluidAudio cache is shown as not ready, but the normal primary action is **Download**. If the selected cache is incomplete, pressing Download automatically performs the existing selected-folder repair and then starts a clean FluidAudio download. The user does not need to choose a separate Repair action for normal recovery.

WhisperKit remains a separate engine and retains its existing WhisperKit model catalog, custom import flow, active-model controls, download progress, cancellation, and deletion behavior. Selecting FluidAudio does not route models through WhisperKit.

## Test-first verification

The unchanged full test suite passed with 144 tests and zero failures before implementation. New regression tests were then added for provider-level engine labels and the FluidAudio Download action. They failed against the prior implementation because the engine label was `Parakeet TDT v3` and the UI action contract had no Download title helper. After the minimal implementation, the focused tests passed and the full suite passed with 146 tests and zero failures.

## Scope and non-goals

This is a naming and presentation correction with automatic recovery retained underneath. It does not change the FluidAudio v2/v3 model formats, local-only transcription boundary, validation rules, download destination, or true-streaming status. Real model downloading and inference remain manual Apple Silicon verification steps.

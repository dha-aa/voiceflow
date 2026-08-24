# Specification Change 019 — FluidAudio Model Management

## Summary

This change makes FluidAudio model management behave like WhisperKit while keeping the providers separate. The Models pane now shows only the selected provider’s models: WhisperKit catalog rows when WhisperKit is selected, and FluidAudio Parakeet TDT v2/v3 rows when FluidAudio is selected.

## Implemented behavior

The speech-engine picker presents **WhisperKit** and **FluidAudio**. Parakeet v2 and v3 are models belonging to the FluidAudio provider, not separate providers. FluidAudio rows show their own validation state, **Download**, progress, **Cancel**, **Downloaded**, **Active**, **Set Active**, and **Open Folder** states. WhisperKit rows are hidden while FluidAudio is selected, and FluidAudio rows are hidden while WhisperKit is selected.

A successful FluidAudio download performs structural validation and FluidAudio loading before the variant is marked downloaded. The selected downloaded variant is the active FluidAudio model, and the app requests Parakeet engine preload immediately after successful validation. Selecting another downloaded FluidAudio variant persists that selection and requests the corresponding engine session to replace the prior cached session. Selecting a not-yet-downloaded row starts its own variant’s download flow.

The manager now accepts an injectable base directory for deterministic tests and reports downloaded status per v2/v3 variant. The production cache remains app-owned and variant-specific. WhisperKit’s catalog, active model, download coordinator, import flow, and cached model session remain independent.

## Test-first verification

The unchanged full suite passed with 144 tests and zero failures before implementation. New provider-specific regression tests were then added and failed against the previous implementation because the provider visibility and FluidAudio catalog contracts were absent. After implementation, focused provider/Parakeet tests passed with 25 tests and zero failures, followed by the complete suite with 148 tests and zero failures.

## Scope and limits

No remote speech transcription was introduced. FluidAudio v2/v3 remain local finalized-audio batch engines, and real multi-gigabyte download/inference testing remains a manual Apple Silicon verification step.

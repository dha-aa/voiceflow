# Specification Change 015 — Parakeet Download UI Reliability

## Summary

This corrective change addresses three regressions reported during manual testing: the Parakeet controls made the Models pane overflow, the download operation was not owned by a persistent cancellable task, and the UI did not expose a Cancel action for Parakeet downloads.

## Implemented changes

- Moved the complete speech-engine and model-management content into the Models pane’s scrollable region so long validation messages and model rows no longer expand past the Settings window.
- Replaced the wide one-line Parakeet status row with a compact two-row card. Long diagnostics are limited and truncated rather than forcing the window wider or taller.
- Added manager-owned `isLoading`, `progress`, `isCancelling`, `errorMessage`, and operation identity state for Parakeet downloads.
- Added `startDownload(force:)`, `cancelDownload()`, and `dismissError()` to `ParakeetModelManager`, keeping download state independent of SwiftUI view recreation and tab navigation.
- Added a visible **Cancel** button during Parakeet downloads, with a **Cancelling…** state while FluidAudio unwinds the task.
- Propagated task cancellation into the FluidAudio download call and explicitly checked cancellation before validation and before accepting the model.
- On cancellation or failure, the selected Parakeet variant is refreshed and is never reported as installed unless structural validation and FluidAudio loading have completed successfully.
- Added an injected FluidAudio download operation seam for deterministic cancellation tests without downloading multi-gigabyte model weights.
- Preserved the existing WhisperKit `ModelDownloadCoordinator` cancellation flow and kept WhisperKit model state independent.

## Download contract

The supported flow is:

```text
Start → FluidAudio download → progress → Cancel or completion
                              ↓
                     structural validation
                              ↓
                      FluidAudio load check
                              ↓
                         Installed state
```

Cancellation must stop the task, leave the model uninstalled unless it was already valid before the operation, preserve an actionable validation state, and allow a later retry. A failure must surface an error and must not produce a false-ready Parakeet model.

## UI contract

The Models view keeps the fixed Settings window usable at its existing size. The speech-engine picker, Parakeet variant picker, provenance text, validation status, progress, Cancel/Repair/Open Folder actions, WhisperKit rows, and model-location controls are all reachable through scrolling. Switching tabs must not cancel or erase a Parakeet download.

## Verification

The production target builds successfully with the corrected UI and manager. The new deterministic cancellation test must verify that cancellation is observed, `isLoading` and `isCancelling` return to false, and `isInstalled` remains false. The focused and full XCTest suites must pass before delivery. Real Parakeet download and inference remain manual Apple Silicon checks using the supported FluidInference Core ML conversion.

# Specification Change 017 — Parakeet Repair Cache Reset

## Summary

This change fixes the Repair action shown in the Models screenshots. Both Parakeet v2 and v3 had stale partial cache folders containing an incomplete `Decoder.mlmodelc`, so the UI correctly reported them as not ready but Repair did not explicitly remove the selected stale folder before starting a fresh download.

## Test-first process

The repository was inspected without changes and the existing full suite was run first: 143 tests passed with zero failures. A new regression test was then added for removing a stale partial cache. The test failed against the previous implementation because `ParakeetModelManager.repairModel` did not exist. The smallest implementation was added, and the focused Repair test passed. The complete suite then passed with 144 tests and zero failures.

## Implemented behavior

`ParakeetModelManager.repair()` now removes only the selected variant’s app-owned cache folder, refreshes validation state, clears stale error state, and starts a new download through the normal manager-owned task. The Models view invokes this operation when the selected variant is incomplete or malformed. A failed deletion is shown to the user and does not start a download.

The operation remains variant-specific: repairing v2 cannot remove v3, WhisperKit files, or unrelated Application Support content. After Repair, the selected variant remains not installed until the complete FluidAudio Core ML artifact set has been downloaded, structurally validated, and loaded successfully by FluidAudio.

## Manual verification

On Apple Silicon, select Parakeet v2 or v3 with a partial cache, press **Repair**, and confirm the stale folder is removed before the fresh download begins. Confirm progress and **Cancel** remain visible during the new download. If the download is cancelled or fails, the variant must remain not ready and be retryable. A real model download and inference were not performed during automated validation.

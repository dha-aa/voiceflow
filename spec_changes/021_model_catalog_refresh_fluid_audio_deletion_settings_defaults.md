# Specification Change 021 — Model Refresh, FluidAudio Deletion, Settings Defaults, and Keychain Removal

## Summary

This change stabilizes the Models settings experience across catalog refreshes and brings FluidAudio model management to parity with WhisperKit where appropriate. It also moves the sidebar control into the Settings toolbar, verifies fresh-install defaults, and strengthens API-key removal so deletion from the macOS Keychain is verified before the UI reports success.

## Catalog refresh state

`ModelManager` now exposes a dedicated observable `isRefreshing` state. `refreshModels()` sets this state before the asynchronous catalog request and clears it with `defer` on both success and failure. Concurrent refresh requests are ignored while one refresh is active. The existing `isLoading` state remains associated with model download work and is not used to represent catalog refreshes.

`ModelsSettingsView` renders the catalog spinner only while `modelManager.isRefreshing` is true. It no longer treats model download loading as catalog refresh activity, so a download cannot produce a misleading “Refreshing model catalog…” spinner. The refresh button and import controls are disabled while a real catalog refresh is active. Successful refreshes replace `availableModels` using the latest remote catalog and local validation results; failed refreshes clear the refresh state without replacing the last valid catalog.

## FluidAudio model deletion and layout

`ParakeetModelManager.delete(_:)` accepts any downloaded `ParakeetModelVariant`, removes only that variant’s managed local directory, refreshes validation, and emits `onModelAvailabilityChanged` so the engine and UI update immediately. If the deleted variant is selected, the manager promotes another installed variant when one exists and persists that replacement. If no replacement exists, it removes the persisted selected-variant value and leaves the deleted variant non-installed and non-active in memory.

The FluidAudio row now offers **Delete** for every downloaded variant, with a confirmation alert matching the WhisperKit destructive-action flow. The delete operation updates downloaded and active indicators immediately and reports failures through the existing model-action error surface. The row no longer places **Open Folder** beside the model action. FluidAudio now has a provider footer containing its managed model path and an **Open in Finder** action, matching the WhisperKit section’s layout pattern.

## Sidebar navigation

`SettingsView` binds `NavigationSplitView` column visibility and removes the automatic sidebar toggle. A controlled toolbar item in the navigation placement provides **Hide Sidebar** and **Show Sidebar** labels and toggles between `.all` and `.detailOnly`. The settings destination list and detail navigation remain unchanged.

## Fresh-install defaults

The existing defaults are explicitly verified for a fresh `UserDefaults` domain. Claude commands and Grammar Fix are disabled unless the user enables them. Completion sound playback is disabled unless the user enables it; the stored effect fallback remains harmless because no sound is played while playback is disabled. Onboarding and first launch do not set any AI or sound feature to enabled.

## API-key storage and removal

Claude API keys continue to be stored only in the provider-specific macOS Keychain item. The UI removal path calls `KeychainAPIKeyStore.remove()`, immediately clears its configured-key state, exits edit/display masking state appropriately, clears the fetched model list, and reports the new unconfigured state. `KeychainAPIKeyStore.remove()` deletes the service/account item and verifies that a subsequent read cannot retrieve a value; missing items remain an idempotent success. Saving a later key continues to remove any prior item before adding the replacement with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.

## Privacy and compatibility requirements

No audio or transcription data is sent to the network by model refresh or FluidAudio deletion. Catalog refresh logs remain metadata-only. API keys, model contents, prompts, responses, and dictated text are not logged. Existing WhisperKit download, validation, active-model protection, model preloading, local FluidAudio inference, overlay, injection, completion sound, and menu-bar behavior remain unchanged outside the explicitly described settings fixes.

## Test-first verification

The unchanged baseline suite completed before implementation with **154 tests and zero failures**. The new regression tests were then run against the previous implementation and failed to compile because the dedicated refresh state, FluidAudio deletion UI policy, sidebar policy, and variant-aware deletion API were absent. After implementation, the focused regression set completed with **6 tests and zero failures**. The complete suite completed with **160 tests and zero failures**.

## Acceptance criteria

| Area | Acceptance criterion |
|---|---|
| Refresh spinner | The catalog spinner is visible only while `ModelManager.isRefreshing` is true and stops on both success and failure. |
| Refresh results | A successful refresh replaces the catalog with current remote/local discovery results; a failed refresh preserves the prior catalog and clears transient state. |
| FluidAudio delete | Every downloaded FluidAudio variant exposes Delete and removes its managed directory after confirmation. |
| Active state | Deleting the selected variant clears the persisted selection or selects another installed variant, and the deleted row is never active or downloaded. |
| Finder layout | FluidAudio exposes its model path and Open in Finder in a footer consistent with WhisperKit. |
| Sidebar | Hide Sidebar/Show Sidebar is controlled from the Settings navigation toolbar rather than an unrelated layout position. |
| Defaults | AI commands, Grammar Fix, and completion-sound playback are all off in a fresh defaults domain. |
| Keychain | Removing a key deletes the provider-specific Keychain item, verifies it is no longer readable, and immediately clears UI state. |
| Validation | All 160 XCTest cases pass after implementation. |

## Scope and limits

This change does not alter remote catalog contents, add a new provider, change the completion-sound effect catalog, or delete user models without confirmation. Actual Finder presentation and Keychain behavior remain subject to macOS permissions and services; deterministic tests cover the manager and storage contracts, while manual verification should cover refresh success/failure, FluidAudio deletion with and without a replacement, sidebar toggling, fresh launch defaults, and remove/re-add API-key flows.

# SPEC 06 — Settings Window and WhisperKit Model Management UI

## Status and dependency

Specification 06 adds the administrative UI on top of the complete core pipeline and overlay from Specifications 01–05. It is a consumer of the existing `ModelManager`, `AppStateManager`, overlay preference contract, and menu-bar popover. It must not recreate the status item, replace the `NSPopover`, or change recording/transcription/injection behavior.

The current Settings window has three destinations: **General**, **Models**, and **About**. The implementation uses explicit sidebar buttons because relying on implicit `NavigationSplitView` list selection caused the original sections to be non-clickable.

## 1. Goals

The Settings layer must let users:

- Understand the always-enabled Fn push-to-talk behavior.
- Enable or disable launch at login through `SMAppService.mainApp`.
- Enable/disable the recording overlay and configure success feedback.
- Refresh the live WhisperKit model catalog.
- Download models with persistent progress and cancellation.
- See models only as installed after structural and real load validation succeeds.
- Select one valid installed model as active.
- Delete inactive models with confirmation and prevent active-model deletion.
- Open the app-owned model directory in Finder.
- View app version/build, WhisperKit attribution, repository links, and license information.

## 2. Components and contracts

| Component | Location | Current responsibility |
|---|---|---|
| `SettingsWindowController` | `voiceflow/UI/Settings/SettingsWindowController.swift` | Singleton Settings window lifecycle and fixed geometry |
| `SettingsView` | `voiceflow/UI/Settings/SettingsView.swift` | Three-destination sidebar and detail routing |
| `GeneralSettingsView` | `voiceflow/UI/Settings/GeneralSettingsView.swift` | General preferences and launch-at-login |
| `ModelsSettingsView` | `voiceflow/UI/Settings/ModelsSettingsView.swift` | Model catalog, actions, progress, alerts, and Finder access |
| `ModelDownloadCoordinator` | `voiceflow/UI/Settings/ModelDownloadCoordinator.swift` | Long-lived download task, progress, cancel, and error state |
| `AboutSettingsView` | `voiceflow/UI/Settings/AboutSettingsView.swift` | Branding, metadata, links, and license |
| `MenuBarPopoverView` | `voiceflow/UI/Popover/MenuBarPopoverView.swift` | Settings entry point and active model/status summary |

The AppDelegate passes the shared `ModelManager` to `SettingsWindowController.shared.show(modelManager:)`. The window controller retains the same manager and a long-lived `ModelDownloadCoordinator`. Reopening Settings rebuilds the SwiftUI root view but preserves the manager and any active download.

## 3. Settings window

`SettingsWindowController` is a main-actor singleton. The first window uses an intended content size of **760×500 pt** and a minimum content size of **680×420 pt**. It is a standard titled, closable, miniaturizable, resizable `NSWindow`, not an overlay panel. Closing it does not terminate the menu-bar app.

Each `show(modelManager:)` call updates the retained manager, reuses the download coordinator when the manager is unchanged, recreates the SwiftUI root view, resets the window geometry to the intended size, brings it frontmost, and activates the application. This prevents the window from shrinking after switching tabs or reopening it.

`SettingsView.Destination` is the `Hashable` enum `general`, `models`, and `about`. The sidebar uses explicit `Button` controls with a visual selection background. The detail pane renders exactly one of `GeneralSettingsView`, `ModelsSettingsView`, or `AboutSettingsView`.

## 4. General settings

`GeneralSettingsView` uses `@AppStorage` and the following keys/defaults:

| Key | Default | Behavior |
|---|---:|---|
| `showRecordingOverlay` | `true` | Controls whether the transient overlay is shown |
| `playCompletionSound` | `false` | Controls success-only completion audio |
| `completionSoundEffect` | `Tink` | Selected `CompletionSoundEffect` raw value |

The pane contains these sections:

- **Push-to-Talk:** displays `Hold Fn to Talk`, `Enabled`, and `Hold Fn to record. Release Fn to transcribe.` The feature is currently always enabled and has no toggle.
- **Startup:** controls `Launch VoiceFlow at Login` through `SMAppService.mainApp.register()` and `.unregister()`. It displays enabled, approval-required, not-registered, or unavailable status and shows registration errors inline.
- **Feedback:** controls `Play completion sound` and a disabled-until-enabled picker containing `Tink`, `Pop`, and `Glass`. The actual playback remains owned by `InjectionCoordinator` and occurs only after successful injection.
- **Appearance:** controls `Show recording overlay when recording` and explains that the overlay does not take focus.

Changing the overlay setting takes effect through `UserDefaults.didChangeNotification` without relaunching. Completion sound preferences are read by the injection coordinator and persist across launches.

## 5. Models pane

`ModelsSettingsView` binds to the shared `ModelManager` and the long-lived `ModelDownloadCoordinator`. It contains a refresh control, `Installed Models` and `Available to Download` sections, and a `Model location` area showing the canonical path with an **Open in Finder** button.

The pane does not hardcode model names, sizes, or installation state. It renders the current `availableModels` supplied by `ModelManager`, partitioned by `isDownloaded`. The manager’s valid installation contract is described in Specification 03.

Each row displays the derived model name, a recommended marker when applicable, a size or `Size unknown`, Downloaded status for installed models, and an active indicator. Actions are:

| Row state | Available actions |
|---|---|
| Installed and active | `Active`; Delete requests the active-model guard and never deletes immediately |
| Installed and inactive | `Set Active`, `Delete` with confirmation |
| Not installed | `Download`; disabled when another download is active |
| Active download | Linear progress, percentage, and `Cancel`/`Cancelling…` |

`Set Active` calls `ModelManager.selectModel(id:)`. Only a preflight-valid installed model can become selected, and selection changes trigger transcription-engine replacement/preload.

`Download` calls `ModelDownloadCoordinator.startDownload(id:)`. The coordinator keeps `activeModelID`, `progress`, `errorMessage`, and `isCancelling` outside the SwiftUI view lifecycle, so switching to General or About does not stop or erase progress. The download task invokes `ModelManager.downloadModel`, clamps progress, refreshes the model list after completion, and clears transient state. Cancellation cancels the task and does not report a false successful installation.

After a model download, `ModelManager` validates the exact SDK-returned folder, checks required Core ML components, confirms the path is inside the app-owned root, optionally loads it through WhisperKit, and only then marks it installed. Validation or load failure is shown as an actionable alert and the failed artifact is removed when safe.

The pane shows a destructive confirmation before deleting an inactive model. The active model cannot be deleted. After successful deletion, it refreshes the catalog and local installation state. The Finder button opens `modelManager.downloadBase`, which is the app-owned model root, not a legacy snapshot directory.

## 6. About pane

`AboutSettingsView` shows:

- VoiceFlow branding and `Fast, private voice input for macOS.`
- Version from `CFBundleShortVersionString`.
- Build from `CFBundleVersion`.
- `WhisperKit by Argmax`.
- Links to `https://github.com/dha-aa/voiceflow` and `https://github.com/argmaxinc/argmax-oss-swift`.
- `MIT License`.

The pane is informational and does not perform model or pipeline actions.

## 7. Menu-bar popover integration

`MenuBarPopoverView` remains hosted by the existing transient `NSPopover`. It shows `VoiceFlow`, the state-derived status, the selected model display name or `No active model`, `Settings...`, and `Quit VoiceFlow`. The Settings button calls `SettingsWindowController.shared.show(modelManager:)`; it does not create a second window or replace the popover architecture.

## 8. Tests and verification

The current Settings tests are in `voiceflowTests/UI/SettingsTests.swift` and cover:

- All three destinations and constructible root view.
- Overlay default and persistence.
- Completion sound default, persistence, and effect selection.
- Installed/available model rendering and active selection persistence.
- Download progress, completion, exact-folder validation, and failed WhisperKit load behavior.
- Download progress surviving outside the Models view.
- Blocking deletion of the active model.

Manual verification must confirm:

1. Settings opens from the popover and closes without terminating VoiceFlow.
2. General, Models, and About sidebar controls are all clickable.
3. Reopening Settings restores the intended window size rather than shrinking based on the selected pane.
4. Launch-at-login can be toggled and errors are shown without a crash.
5. Completion sound defaults off, the picker is disabled while off, and Tink/Pop/Glass persist when selected.
6. Overlay visibility changes apply during the next interaction.
7. Models refreshes from the live catalog and separates validated installed models from downloadable models.
8. Download shows progress and Cancel; switching tabs preserves progress; returning to Models shows the active operation.
9. A successful download is validated, load-checked, detected immediately, and reused by transcription.
10. A failed structural or WhisperKit load validation is not shown as installed.
11. Finder opens the canonical app-owned model folder.
12. Active-model deletion is blocked; inactive deletion requires confirmation.
13. Selecting a different installed model triggers replacement/preload before the next recording.
14. About shows correct metadata and links.
15. The core TextEdit pipeline and overlay remain regression-free.

## 9. Acceptance criteria

- The singleton Settings window opens from the existing popover and does not terminate the app when closed.
- General, Models, and About are selectable by explicit working controls.
- The window reopens at its intended 760×500 content size with the 680×420 minimum.
- Launch-at-login uses `SMAppService.mainApp` and displays actionable errors.
- Overlay preference defaults true and persists; completion sound defaults false and persists with Tink/Pop/Glass selection.
- Models are supplied by the live catalog and are not hardcoded in the UI.
- Only preflight-valid, optionally real-load-validated models appear installed.
- Download progress and cancellation survive navigation away from the Models pane.
- Successful download refreshes the list immediately and failed download/load does not mark the model installed.
- The canonical model folder can be opened in Finder.
- Active model deletion is prevented; inactive deletion is confirmed and verified.
- Selection changes are persisted and cause transcription-engine model replacement/preload.
- About metadata and repository links are accurate.
- All Settings tests pass and the complete core pipeline remains functional.

## 10. Handoff to Specification 07

Specification 07 receives a complete feature implementation with known persistence, model lifecycle, overlay, permission, and pipeline contracts. It must focus on production hardening, privacy-safe diagnostics, CI, unsigned/signed release packaging, and distribution verification; it must not invent a second Settings or model lifecycle.

## References

[1]: ../voiceflow/UI/Settings/SettingsWindowController.swift "Settings window lifecycle"
[2]: ../voiceflow/UI/Settings/SettingsView.swift "Settings navigation"
[3]: ../voiceflow/UI/Settings/GeneralSettingsView.swift "General settings and defaults"
[4]: ../voiceflow/UI/Settings/ModelsSettingsView.swift "Models settings UI"
[5]: ../voiceflow/UI/Settings/ModelDownloadCoordinator.swift "Persistent model download state"
[6]: ../voiceflow/UI/Settings/AboutSettingsView.swift "About pane"
[7]: ../voiceflow/UI/Popover/MenuBarPopoverView.swift "Menu-bar popover integration"
[8]: ../voiceflow/Core/Transcription/ModelManager.swift "Canonical model lifecycle"
[9]: ../voiceflow/Core/Transcription/TranscriptionEngine.swift "Model preload and replacement"
[10]: ../voiceflowTests/UI/SettingsTests.swift "Settings and model-management tests"
[11]: ../voiceflow/Core/Injection/InjectionCoordinator.swift "Completion sound persistence and playback"

## Implementation inconsistency register

The historical specification expected an implicit `NavigationSplitView` list selection and did not include completion sound, persistent download progress, cancellation, Finder navigation, fixed reopen geometry, exact-folder validation, or real load validation. The current implementation intentionally includes all of these behaviors. The old snapshot-path and “directory exists means installed” model rules are superseded by Specification 03.

## Completion gate

Do not begin Specification 07 until all Settings tests pass, all three panes are manually verified, model download/validation/load/detection works on a real model, progress survives tab navigation, and the core pipeline remains operational after changing settings or the active model.

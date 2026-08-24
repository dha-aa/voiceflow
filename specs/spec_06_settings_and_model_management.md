# SPEC 06 — Settings Window and WhisperKit Model Management UI

## Status and dependency

Specification 06 adds the administrative UI on top of the complete core pipeline and overlay from Specifications 01–05. It is a consumer of the existing `ModelManager`, `AppStateManager`, overlay preference contract, and menu-bar popover. It must not recreate the status item, replace the `NSPopover`, or change recording/transcription/injection behavior.

The current Settings window has four destinations: **General**, **AI**, **Models**, and **About**. The implementation uses explicit sidebar buttons because relying on implicit `NavigationSplitView` list selection caused the original sections to be non-clickable.

## 1. Goals

The Settings layer must let users:

- Understand the always-enabled Fn push-to-talk behavior.
- Enable or disable launch at login through `SMAppService.mainApp`.
- Enable/disable the recording overlay and configure success feedback.
- Choose the default AI provider, configure Claude securely, and persist the selected model.
- Fetch the Claude model list from Anthropic after the user requests a refresh.
- Refresh the live WhisperKit model catalog.
- Download models with persistent progress and cancellation.
- Import a local WhisperKit Core ML model folder through a native folder picker.
- See models only as installed after structural and real load validation succeeds.
- Select one valid installed model as active.
- Delete inactive models with confirmation and prevent active-model deletion.
- Open the app-owned model directory in Finder.
- View app version/build, WhisperKit attribution, repository links, and license information.

## 2. Components and contracts

| Component | Location | Current responsibility |
|---|---|---|
| `SettingsWindowController` | `voiceflow/UI/Settings/SettingsWindowController.swift` | Singleton Settings window lifecycle and fixed geometry |
| `SettingsView` | `voiceflow/UI/Settings/SettingsView.swift` | Four-destination sidebar and detail routing |
| `GeneralSettingsView` | `voiceflow/UI/Settings/GeneralSettingsView.swift` | General preferences and launch-at-login |
| `AISettingsView` | `voiceflow/UI/Settings/AISettingsView.swift` | Provider selection, Claude credentials, model selection, and model refresh |
| `AIProcessing` | `voiceflow/Core/LLM/AIProcessing.swift` | Provider-neutral request modes, compact prompts, optional screen-context slot, and provider-client contract |
| `ModelsSettingsView` | `voiceflow/UI/Settings/ModelsSettingsView.swift` | Model catalog, download/import actions, progress, alerts, and Finder access |
| `ModelDownloadCoordinator` | `voiceflow/UI/Settings/ModelDownloadCoordinator.swift` | Long-lived download task, progress, cancel, and error state |
| `AboutSettingsView` | `voiceflow/UI/Settings/AboutSettingsView.swift` | Branding, metadata, links, and license |
| `MenuBarPopoverView` | `voiceflow/UI/Popover/MenuBarPopoverView.swift` | Settings entry point and active model/status summary |

The AppDelegate passes the shared `ModelManager` to `SettingsWindowController.shared.show(modelManager:)`. The window controller retains the same manager and a long-lived `ModelDownloadCoordinator`. Reopening Settings rebuilds the SwiftUI root view but preserves the manager and any active download.

## 3. Settings window

`SettingsWindowController` is a main-actor singleton. The first window uses an intended content size of **760×500 pt** and a minimum content size of **680×420 pt**. It is a standard titled, closable, miniaturizable, resizable `NSWindow`, not an overlay panel. Closing it does not terminate the menu-bar app.

Each `show(modelManager:)` call updates the retained manager, reuses the download coordinator when the manager is unchanged, recreates the SwiftUI root view, resets the window geometry to the intended size, brings it frontmost, and activates the application. This prevents the window from shrinking after switching tabs or reopening it.

`SettingsView.Destination` is the `Hashable` enum `general`, `ai`, `models`, and `about`. The sidebar uses explicit `Button` controls with a visual selection background. The detail pane renders exactly one of `GeneralSettingsView`, `AISettingsView`, `ModelsSettingsView`, or `AboutSettingsView`.

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
- **Permissions:** shows current Microphone and Accessibility status with **Grant Permission** and **Open System Settings** recovery actions. It explains that Screen Recording is reserved for a future screen-context feature and is not requested by the current version.

Changing the overlay setting takes effect through `UserDefaults.didChangeNotification` without relaunching. Completion sound preferences are read by the injection coordinator and persist across launches. Permission status refreshes when the app becomes active after the user visits System Settings.

### AI settings

`AISettingsView` is the single settings surface for AI provider configuration. `AIProvider` currently contains `claude` and a disabled `chatGPT` future case. The selected provider is persisted in `aiSelectedProvider`, defaulting to Claude. Provider model selections use per-provider keys such as `aiModel.claude`; the prior `claudeModel` key is read as a migration fallback. Claude commands remain disabled by default through `claudeCommandsEnabled`.

Claude API keys are saved only through the provider-neutral `KeychainAPIKeyStore`, using a provider-specific Keychain account (`anthropic-api-key` for Claude). After saving, the AI pane shows a fixed masked value and `Configured` status, with explicit `Change API Key` and `Remove API Key` controls. The stored secret is never displayed or copied into UserDefaults. Claude’s custom command prefix defaults to `Claude`, is persisted in `aiCommandPrefix`, and may be any non-empty word or phrase. Claude’s model can be entered manually or refreshed through the user-triggered **Fetch available models** action, which calls Anthropic’s authenticated `GET /v1/models` endpoint and presents the returned model IDs/display names. The last successful list is kept in view; a refresh failure does not erase the manually selected model. **Fix Grammar & Punctuation** is an independent opt-in toggle persisted in `grammarFixEnabled`. It uses Claude only for ordinary transcripts without a matching AI prefix and instructs Claude to return corrected text only. ChatGPT has no active key, model-list request, or generation path yet and must be presented as coming soon rather than as an operational provider.

A Claude command is eligible for routing only when Claude commands are enabled, Claude is the selected provider, and the locally processed transcript begins with the configured prefix. Matching is case-insensitive and requires a word boundary after the prefix; optional punctuation and whitespace are removed from the remainder. When this route is active, the overlay changes its processing status to `Using Claude...`; a future provider route must use the corresponding provider title. The existing transcription coordinator continues to perform local WhisperKit transcription first, then routes the remaining text through the selected Claude model before handing the final text to injection.

The processor checks the AI prefix before Grammar Fix. The four cases are: a matching prefix with Grammar Fix on routes only the prefix remainder as an AI request; a matching prefix with Grammar Fix off behaves the same; no prefix with Grammar Fix on sends the complete ordinary transcript through Claude’s correction-only system prompt; and no prefix with Grammar Fix off leaves the local processed text unchanged. Grammar Fix must never alter an AI command before command routing.

`AIProcessingRequest` is the provider-neutral request shape. It carries the instruction text, processing mode, selected provider model, optional selected text, and optional `AIScreenContext`. `AIPromptBuilder` supplies reusable command and Grammar Fix system-prompt modes. `AIProviderClient` is the future-provider boundary; Claude currently implements it through `ClaudeAIProviderClient`, while ChatGPT remains disabled UI only. For an explicit AI command, `FocusedTextSelectionReading` may read only the focused element’s selected text through Accessibility. A non-empty selection is the narrowest context: it is sent with the instruction, the broader screen-context provider is not called, and the final response replaces the selection through the existing injection path. The current app does not capture screen context, but the request slot remains ready for a future privacy-reviewed screen-context provider.

## 5. Models pane

`ModelsSettingsView` binds to the shared `ModelManager` and the long-lived `ModelDownloadCoordinator`. It contains refresh and **Import Model** controls, `Installed Models` and `Available to Download` sections, and a `Model location` area showing the canonical path with an **Open in Finder** button.

The pane does not hardcode model names, sizes, or installation state. It renders the current `availableModels` supplied by `ModelManager`, partitioned by `isDownloaded`. The manager’s valid installation contract is described in Specification 03.

Each row displays the derived model name, a recommended marker when applicable, a size or `Size unknown`, Downloaded status for installed models, and an active indicator. Actions are:

| Row state | Available actions |
|---|---|
| Installed and active | `Active`; Delete requests the active-model guard and never deletes immediately |
| Installed and inactive | `Set Active`, `Delete` with confirmation |
| Not installed | `Download`; disabled when another download is active |
| Active download | Linear progress, percentage, and `Cancel`/`Cancelling…` |
| Importing | Native folder picker followed by staging, validation, load validation, and managed promotion |

`Set Active` calls `ModelManager.selectModel(id:)`. Only a preflight-valid installed model can become selected, and selection changes trigger transcription-engine replacement/preload.

`Download` calls `ModelDownloadCoordinator.startDownload(id:)`. The coordinator keeps `activeModelID`, `progress`, `errorMessage`, and `isCancelling` outside the SwiftUI view lifecycle, so switching to General or About does not stop or erase progress. The download task invokes `ModelManager.downloadModel`, clamps progress, refreshes the model list after completion, and clears transient state. Cancellation cancels the task and does not report a false successful installation.

After a model download, `ModelManager` validates the exact SDK-returned folder, checks required Core ML components, confirms the path is inside the app-owned root, optionally loads it through WhisperKit, and only then marks it installed. Validation or load failure is shown as an actionable alert and the failed artifact is removed when safe.

`Import Model` opens a native macOS folder picker. The selected folder must match the registered custom model folder name `Oriserve_Whisper-Hindi2Hinglish-Prime_889MB` and contain `MelSpectrogram.mlmodelc`, `AudioEncoder.mlmodelc`, and `TextDecoder.mlmodelc` directly inside it. The manager copies the source into a temporary staging directory under `models/nitinh/whisperkit-hinglish-coreml/`, performs the same structural checks, optionally runs real WhisperKit load validation with the remote model ID `Oriserve_Whisper-Hindi2Hinglish-Prime_889MB`, and moves the staged folder into its final managed location only after validation succeeds. Source symlinks, invalid folder names, duplicate installs, invalid components, and failed load validation are rejected without exposing a partial installation. The importer uses security-scoped access only for the duration of the copy and does not upload the model or add network behavior to transcription.

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

- All four destinations and constructible root view.
- Overlay default and persistence.
- Completion sound default, persistence, and effect selection.
- Installed/available model rendering and active selection persistence.
- Download progress, completion, exact-folder validation, and failed WhisperKit load behavior.
- Custom Oriserve folder import, staging, validation, duplicate rejection, and alias-to-remote-ID resolution.
- Download progress surviving outside the Models view.
- Blocking deletion of the active model.

Manual verification must confirm:

1. Settings opens from the popover and closes without terminating VoiceFlow.
2. General, AI, Models, and About sidebar controls are all clickable.
3. Reopening Settings restores the intended window size rather than shrinking based on the selected pane.
4. Launch-at-login can be toggled and errors are shown without a crash.
5. Completion sound defaults off, the picker is disabled while off, and Tink/Pop/Glass persist when selected.
6. Overlay visibility changes apply during the next interaction.
7. Models refreshes from the live catalog and separates validated installed models from downloadable models.
8. Download shows progress and Cancel; switching tabs preserves progress; returning to Models shows the active operation.
9. Import Model accepts the Oriserve folder, shows import/validation progress, detects the installed model immediately, and rejects invalid or duplicate folders safely.
10. A successful download or import is validated, load-checked, detected immediately, and reused by transcription.
11. A failed structural or WhisperKit load validation is not shown as installed.
12. The AI pane defaults to Claude, Claude commands are disabled by default, the custom prefix defaults to `Claude` and persists, the Grammar Fix toggle defaults to off and persists, and the Claude model ID is editable.
13. The API-key UI shows a masked value and `Configured` after saving, and supports `Change API Key` and `Remove API Key` without exposing the secret.
14. Fetch available models uses the saved Claude key, updates the available Claude model choices, and leaves the current selection usable when the refresh fails.
15. A transcript beginning with the configured prefix sends only the remaining text to Anthropic and injects the returned text; a normal transcript sends no network request unless the independent Grammar Fix toggle is enabled, in which case the complete ordinary transcript uses the correction-only Claude path.
16. Finder opens the canonical app-owned model folder.
17. Active-model deletion is blocked; inactive deletion requires confirmation.
18. Selecting a different installed model triggers replacement/preload before the next recording.
19. About shows correct metadata and links.
20. All General and AI toggles retain the native switch appearance after repeated Settings-window reopenings.
21. The core TextEdit pipeline and overlay remain regression-free.

## 9. Acceptance criteria

- The singleton Settings window opens from the existing popover and does not terminate the app when closed.
- General, AI, Models, and About are selectable by explicit working controls.
- First launch presents the welcome and sequential permission onboarding; skipped or denied permissions remain recoverable from General → Permissions.
- The window reopens at its intended 760×500 content size with the 680×420 minimum.
- Launch-at-login uses `SMAppService.mainApp` and displays actionable errors.
- Overlay preference defaults true and persists; completion sound defaults false and persists with Tink/Pop/Glass selection.
- The AI pane defaults to Claude, Claude commands default to disabled, Grammar Fix defaults to disabled, Claude uses a Keychain-stored API key with masked Configured/Change/Remove UX, exposes a persisted custom prefix and editable or fetched model choice, and routes only the configured-prefix remainder before any Grammar Fix processing. Ordinary no-prefix speech uses the correction-only Claude path only when Grammar Fix is enabled. The provider-neutral request and prompt contract carries mode, model, selected text, and optional screen context for future providers. When selected text is available, only that text plus the instruction is sent and the response replaces the selection. The overlay identifies the active provider while the request is in progress. ChatGPT is visibly future work and makes no request.
- Models are supplied by the live catalog and are not hardcoded in the UI.
- Only preflight-valid, optionally real-load-validated models appear installed.
- Download progress and cancellation survive navigation away from the Models pane.
- Successful download or custom-folder import refreshes the list immediately, and failed validation/load does not mark the model installed.
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
[4]: ../voiceflow/UI/Settings/AISettingsView.swift "AI provider and Claude settings UI"
[5]: ../voiceflow/UI/Settings/ModelsSettingsView.swift "Models settings UI"
[6]: ../voiceflow/UI/Settings/ModelDownloadCoordinator.swift "Persistent model download state"
[7]: ../voiceflow/UI/Settings/AboutSettingsView.swift "About pane"
[8]: ../voiceflow/UI/Popover/MenuBarPopoverView.swift "Menu-bar popover integration"
[9]: ../voiceflow/Core/Transcription/ModelManager.swift "Canonical model lifecycle"
[10]: ../voiceflow/Core/Transcription/TranscriptionEngine.swift "Model preload and replacement"
[11]: ../voiceflowTests/UI/SettingsTests.swift "Settings and model-management tests"
[12]: ../voiceflow/Core/Injection/InjectionCoordinator.swift "Completion sound persistence and playback"
[13]: ../voiceflow/Core/LLM/AISettings.swift "AI provider settings and Keychain contracts"
[14]: ../voiceflow/Core/LLM/AIModelCatalog.swift "Claude model discovery"

## Implementation inconsistency register

The historical specification expected an implicit `NavigationSplitView` list selection and did not include completion sound, persistent download progress, cancellation, Finder navigation, fixed reopen geometry, exact-folder validation, or real load validation. The current implementation intentionally includes all of these behaviors. The old snapshot-path and “directory exists means installed” model rules are superseded by Specification 03.

## Completion gate

Do not begin Specification 07 until all Settings tests pass, all four panes are manually verified, Claude key/model configuration and model refresh are checked with a user-owned key, model download/validation/load/detection works on a real model, progress survives tab navigation, and the core pipeline remains operational after changing settings or the active model.

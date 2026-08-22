# SPEC 06 — Settings Window & Model Management UI

## 1. Purpose

This specification implements the Settings window and the model management UI — the administrative surface of VoiceFlow where users configure the application, manage WhisperKit models, and view application information.

By this point, the full core pipeline and recording overlay are working. This spec adds the settings layer that allows users to control the behavior they have already verified works correctly.

---

## 2. Scope

- Implement the Settings window as a native macOS sidebar-style window.
- Implement the **General** settings pane: push-to-talk status, launch at login toggle, overlay toggle.
- Implement the **Models** settings pane: installed model list, active model selection, model download, model deletion.
- Implement the **About** pane: app version, model engine info, links.
- Populate the existing `MenuBarPopoverView` to show the currently selected model name and provide access to Settings.
- Do NOT recreate or redesign the menu bar infrastructure. Spec 01 already establishes the `NSPopover`-based menu bar architecture. Spec 06 must consume this existing architecture and only modify the popover content view.

---

## 3. Out of Scope

Do NOT implement any of the following in this specification:

- Changes to the core pipeline (Specs 01–04).
- Changes to the recording overlay (Spec 05).
- New Fn key detection logic.
- New transcription or injection logic.
- Final production polish, app signing, or distribution (Spec 07).

---

## 4. Dependencies

**Specs 01–05 must be complete and verified before starting this spec.**

Required from Spec 01:
- `MenuBarController` and `MenuBarPopoverView` — the established popover architecture. Spec 06 must NOT replace `NSPopover`, introduce `NSMenu`, rewrite `MenuBarController`, recreate the status item, or rebuild the popover infrastructure.

Required from Spec 03:
- `ModelManager` — stable API for model discovery, selection, download, deletion.
  - `availableModels: [WhisperModel]`
  - `selectedModelId: String?`
  - `selectModel(id:)`
  - `downloadModel(id:) async throws`
  - `deleteModel(id:) throws`
  - `refreshModels() async`

No new framework dependencies required. SwiftUI + AppKit.

---

## 5. Implementation Requirements

### 5.1 Settings Window

Implement `SettingsWindowController` in `UI/Settings/SettingsWindowController.swift`.

The Settings window:
- Is a standard `NSWindow` (not a panel) with a title bar.
- Uses the macOS Settings-style sidebar layout.
- Closes when the user clicks the red close button.
- Does not terminate the application when closed.
- Can be re-opened from the menu bar popover "Settings" button.
- Does not take over the main menu bar (the app has no menu bar in `LSUIElement` mode).

Use SwiftUI `NavigationSplitView` (macOS 13+) or a `HSplitView` to implement the sidebar layout:

```
┌────────────────────────────────────────────┐
│ VoiceFlow Settings                         │
├──────────────┬─────────────────────────────┤
│ General      │                             │
│ Models       │    [Selected pane content]  │
│ About        │                             │
└──────────────┴─────────────────────────────┘
```

Implement the window controller:

```swift
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    func show() { ... }    // Bring window to front or create if needed
}
```

Use a singleton so calling `show()` brings the existing window to front rather than creating a second window.

### 5.2 General Settings Pane

Implement `GeneralSettingsView` in `UI/Settings/GeneralSettingsView.swift`.

Content:

**Push-to-Talk**
- Static label: "Hold Fn to Talk"
- Status indicator: "Enabled" (always enabled in this version — no toggle needed).
- Descriptive text: "Hold Fn to record. Release Fn to transcribe."

**Launch at Login**
- Toggle: `Launch VoiceFlow at Login`
- Implement using `SMAppService.mainApp` (macOS 13+):
  ```swift
  try SMAppService.mainApp.register()   // enable
  try SMAppService.mainApp.unregister() // disable
  SMAppService.mainApp.status           // current status
  ```

**Show Recording Overlay**
- Toggle: `Show recording overlay when recording`
- Persist with `UserDefaults` (key: `"showRecordingOverlay"`, default: `true`).
- > `OverlayWindowController` is a completed component from Spec 05. Do not modify it. Spec 06 controls overlay visibility strictly through the established `UserDefaults` contract.

### 5.3 Models Settings Pane

Implement `ModelsSettingsView` in `UI/Settings/ModelsSettingsView.swift`.

This pane uses `ModelManager` from Spec 03 directly.

Layout:

```
Models

Installed Models

  [model row]   Whisper Large V3
                626 MB · Downloaded · ● Active
                [Delete] button

  [model row]   Whisper Small
                244 MB · Downloaded
                [Set Active] [Delete] buttons

Available to Download

  [model row]   Whisper Base
                145 MB
                [Download] button

  [model row]   Whisper Tiny
                39 MB
                [Download] button
```

Each row must show:
- Model display name.
- Size description.
- Download status.
- Active/inactive indicator.
- Appropriate action buttons: **Set Active**, **Download**, **Delete**.

Action requirements:
- **Set Active**: Call `ModelManager.selectModel(id:)`. Only one model may be active at a time. Updates immediately.
- **Download**: Call `ModelManager.downloadModel(id:)`. Show a `ProgressView` during download. Disable the button during download. Show error if download fails.
- **Delete**: Call `ModelManager.deleteModel(id:)`. Show a confirmation alert before deleting. Deleting the active model must prompt the user to select another model.

Model list:

**Do NOT hardcode the model list.** WhisperKit provides a remote catalog API that fetches the live list directly from the HuggingFace repository `argmaxinc/whisperkit-coreml`.

Use this API in `ModelManager.refreshModels()`:

```swift
// Fetch all available models from the remote HuggingFace repo
let remoteModelIds: [String] = try await WhisperKit.fetchAvailableModels(
    from: "argmaxinc/whisperkit-coreml",
    matching: ["*"]          // glob — "*" returns all models
)

// Get device-appropriate recommendations
let recommended: ModelSupport = await WhisperKit.recommendedRemoteModels(
    from: "argmaxinc/whisperkit-coreml"
)
// recommended.default  → the default model for this device
// recommended.supported → all models supported on this device
```

The full catalog lives at: https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main

**Mapping remote IDs to display names:**

The remote IDs returned by `fetchAvailableModels` follow the pattern `openai_whisper-<variant>` (e.g., `openai_whisper-large-v3-v20240930_626MB`). Strip the `openai_whisper-` prefix to get the variant name used by `WhisperKit.download(variant:)`.

Build the display name from the variant string with a simple formatter (e.g., replace underscores and hyphens with spaces, capitalize words). Do not maintain a static lookup table.

**Model size:**

The remote API does not return file sizes directly. Two options:
1. After fetching the remote list, compute size from disk for downloaded models using `FileManager` (check the model cache directory).
2. For not-yet-downloaded models, omit the size or show "Size unknown" — do not hardcode it.

Do not hardcode sizes. If they matter for UX, compute them at runtime or omit them.

**Downloading a model:**

```swift
// Download a specific model variant (returns the local URL)
let localURL = try await WhisperKit.download(
    variant: variantId,             // e.g. "large-v3-v20240930_626MB"
    from: "argmaxinc/whisperkit-coreml",
    progressCallback: { progress in
        // Update download progress (0.0 to 1.0)
    }
)
```

Mark models as downloaded by checking whether their directory exists in the WhisperKit model cache directory on disk.

### 5.4 About Pane

Implement `AboutSettingsView` in `UI/Settings/AboutSettingsView.swift`.

Content:
- App name: **VoiceFlow**
- Tagline: "Fast, private voice input for macOS."
- Version: pulled from `Bundle.main.infoDictionary["CFBundleShortVersionString"]`.
- Build: pulled from `Bundle.main.infoDictionary["CFBundleVersion"]`.
- Model engine: "WhisperKit by Argmax"
- Link: VoiceFlow GitHub repository (use the actual project URL).
- License information (brief — "MIT License" or appropriate).

Keep this pane simple. No excessive UI.

### 5.5 Update Menu Bar Popover Content

Update `MenuBarPopoverView` in `UI/Popover/MenuBarPopoverView.swift`:

- This view and the underlying `NSPopover` architecture were already established in Spec 01. Do not recreate or change the `MenuBarController`'s popover presentation logic.
- Update the existing placeholder content to include the real functionality:
  - Keep the app name and status label (driven by `AppStateManager`).
  - Show the currently active model name from `ModelManager.selectedModelId`.
  - Add a functional "Settings" button: calls `SettingsWindowController.shared.show()`.
  - Keep the existing "Quit" button.

---

## 6. Files and Components

### Files to create

| File | Purpose |
|------|---------|
| `UI/Settings/SettingsWindowController.swift` | `NSWindow` lifecycle for Settings |
| `UI/Settings/SettingsView.swift` | Root SwiftUI view with `NavigationSplitView` sidebar |
| `UI/Settings/GeneralSettingsView.swift` | General pane |
| `UI/Settings/ModelsSettingsView.swift` | Models pane |
| `UI/Settings/AboutSettingsView.swift` | About pane |
| `UI/Settings/SettingsView.swift` | Root SwiftUI view with `NavigationSplitView` sidebar |

### Files that may be modified

| File | Permitted change |
|------|----------------|
| `UI/Popover/MenuBarPopoverView.swift` | Update placeholder content with Settings button and model status |
| `App/VoiceFlowApp.swift` | Pass `ModelManager` into Settings views |
| `App/AppDelegate.swift` | Same |

### Files that must NOT be modified

| File | Reason |
|------|--------|
| `Core/State/AppState.swift` | Stable from Spec 01 |
| `Core/State/AppStateManager.swift` | Stable from Spec 01 |
| `Core/Audio/` | Stable from Spec 02 |
| `Core/Transcription/` | Stable from Spec 03 — except `ModelManager` is consumed (not changed) |
| `Core/Injection/` | Stable from Spec 04 |
| `UI/Overlay/RecordingOverlayView.swift` | Stable from Spec 05 |
| `UI/Overlay/WaveformView.swift` | Stable from Spec 05 |

---

## 7. Tests

### Unit Tests: `GeneralSettingsTests.swift`

```
test_launchAtLogin_toggle_registersApp
  Toggle launch at login ON. Assert SMAppService.mainApp.status is enabled.

test_launchAtLogin_toggle_unregistersApp
  Toggle ON, then OFF. Assert SMAppService.mainApp.status is not registered.

test_showRecordingOverlay_defaultIsTrue
  Read UserDefaults "showRecordingOverlay". Assert default value is true.

test_showRecordingOverlay_persistsAfterToggle
  Toggle to false. Read UserDefaults again. Assert false.
```

### Unit Tests: `ModelsSettingsViewTests.swift`

```
test_modelsView_showsInstalledModels
  Mock ModelManager with 2 downloaded models.
  Assert both models appear in the installed section.

test_modelsView_showsActiveModelIndicator
  Mock ModelManager with active model "tiny.en".
  Assert "tiny.en" row shows active indicator.

test_modelsView_downloadButton_triggersDownload
  Tap Download on "base" model.
  Assert ModelManager.downloadModel(id: "base") is called.

test_modelsView_deleteButton_triggersConfirmation
  Tap Delete on "tiny.en".
  Assert a confirmation alert appears before deletion.
```

### Manual Verification

```
test_settingsWindow_opensFromPopover
  Click menu bar icon. Click "Settings". Confirm Settings window opens.
  Confirm window has sidebar with General, Models, About sections.

test_settingsWindow_generalPane
  Open Settings → General.
  Confirm push-to-talk section shows "Hold Fn to Talk" and "Enabled".
  Toggle "Launch at Login". Confirm no crash. Toggle back.
  Toggle "Show recording overlay". Hold Fn. Confirm overlay does/does not appear.

test_settingsWindow_modelsPane
  Open Settings → Models.
  Confirm downloaded models appear in "Installed Models".
  Confirm undownloaded models appear in "Available to Download" with Download buttons.
  Click "Set Active" on a different model. Confirm the active indicator moves.

test_settingsWindow_aboutPane
  Open Settings → About.
  Confirm app name, version, and model engine are shown.

test_popover_rendersUpdatedContent
  Close and reopen Settings. Set active model to "tiny.en".
  Click the menu bar icon. Confirm the existing popover opens.
  Confirm the popover content renders the real settings and model status without rebuilding the popover infrastructure.

test_fullPipeline_withNewModel
  Select a different model in Settings. Close Settings.
  Hold Fn. Speak. Release Fn. Confirm transcription uses the new model.
  (Check console logs or model load messages for confirmation.)
```

---

## 8. Acceptance Criteria

All of the following must be true before this spec is complete:

- [ ] Settings window opens from the "Settings" button in the popover.
- [ ] Settings window has General, Models, and About panes.
- [ ] Launch at Login toggle correctly registers/unregisters the app.
- [ ] "Show recording overlay" toggle hides/shows the overlay during recording.
- [ ] Models pane shows installed and available models correctly.
- [ ] User can select a different model and it becomes active for subsequent transcriptions.
- [ ] User can download a new model with visible progress.
- [ ] User can delete a model with a confirmation prompt.
- [ ] About pane shows correct version and build information.
- [ ] Menu bar popover shows the currently active model name (not a placeholder).
- [ ] All unit tests pass.
- [ ] Core pipeline still works after settings changes (regression).

---

## 9. Completion Gate

**This spec is NOT complete until:**

1. All acceptance criteria are checked off.
2. All unit tests pass.
3. Manual verification is complete.
4. Core pipeline regression test passes.
5. Model selection change is picked up by the transcription engine.

**Do not proceed to Spec 07 until this gate passes.**

---

## 10. Handoff to Spec 07

Spec 07 receives a complete, fully functional VoiceFlow application:

| Component | Status |
|-----------|--------|
| Core pipeline | Verified end-to-end in Spec 04 |
| Recording overlay | Working in Spec 05 |
| Settings window | Working in Spec 06 |
| Model management | Working in Spec 06 |
| State machine | Stable since Spec 01 |

Spec 07 focuses exclusively on production readiness: code quality, edge cases, error handling, performance, accessibility, code signing, and app store/distribution preparation. It does not add new features.

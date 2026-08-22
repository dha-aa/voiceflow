# SPEC 05 — Recording Overlay and Menu-Bar Feedback

## Status and dependency

Specification 05 adds visual feedback on top of the verified core pipeline from Specifications 01–04. The overlay and menu-bar controller are **observers** of core state and audio level. They must not start recording, load models, transcribe, inject text, or alter permission behavior.

The current implementation deliberately uses a compact black capsule with no panel-level shadow, border, or extra backing layer. This is the source of truth for the visual behavior; earlier larger material/border/shadow requirements are obsolete.

## 1. Goals

The UI must tell the user when VoiceFlow is preparing a model, listening, processing/transcribing, completing injection, or reporting an error. It must remain non-activating and not steal focus from the target application. It must work across macOS Spaces, remain lightweight, and respect the persisted overlay visibility preference.

The menu-bar icon must provide state feedback while preserving the existing status-item/popover behavior. The normal VoiceFlow identity image must be a sharp template asset that automatically adapts to Light and Dark Mode.

## 2. Components and contracts

| Component | Location | Current responsibility |
|---|---|---|
| `RecordingOverlayModel` | `voiceflow/UI/Overlay/RecordingOverlayView.swift` | Main-actor observable presentation state and clamped audio level |
| `RecordingOverlayView` | Same file | Compact state-driven capsule content and accessibility labels |
| `WaveformView` | `voiceflow/UI/Overlay/WaveformView.swift` | Twelve-bar deterministic audio-level visualizer |
| `OverlayWindowController` | `voiceflow/UI/Overlay/OverlayWindowController.swift` | Non-activating `NSPanel`, timers, positioning, transitions, and preference handling |
| `MenuBarController` | `voiceflow/UI/MenuBar/MenuBarController.swift` | Persistent status item, popover, state polling, and icon feedback |

The overlay controller is created with the shared `AppStateManager`, the `AudioRecorder` for audio-level sampling, and `UserDefaults`. It exposes diagnostic properties used by tests: `isFocusSafe`, `appearsAcrossSpaces`, `overlayFrame`, and `hasNativePanelShadow`.

## 3. Overlay window contract

`OverlayWindowController` creates a custom `NSPanel` with content size **270×58 pt** and style masks `.borderless` and `.nonactivatingPanel`. The custom panel overrides `canBecomeKey` and `canBecomeMain` to `false`. It is floating, clear, non-opaque, ignores mouse events, and uses collection behavior `.canJoinAllSpaces`, `.stationary`, `.transient`, and `.ignoresCycle`.

The panel is positioned at the horizontal center of `NSScreen.main` or the first available screen, at the visible frame’s minimum Y plus 24 pt. It is not a normal application window and must not appear as a user-managed Mission Control window.

The panel has `hasShadow == false`. The SwiftUI capsule owns the visible surface; no native rectangular shadow, border, clipping layer, or backing shape may appear around it. The panel’s hosting view is transparent.

`start()` positions the panel, applies the current state, polls state approximately every 100 ms, and samples recorder audio level at 30 Hz. `stop()` invalidates timers, cancels the completion animation task, and hides the panel without animation.

## 4. Presentation states and mapping

`RecordingOverlayModel.PresentationState` is:

```swift
enum PresentationState: Equatable {
    case hidden
    case preparingModel
    case listening
    case processing
    case done
    case error(AppError)
}
```

The controller maps shared state as follows:

| `AppState` | Overlay presentation | Visibility and label |
|---|---|---|
| `.idle` | `.hidden` | Fade out/order out, except that an active Done presentation is allowed to finish |
| `.preparingModel` | `.preparingModel` | Visible capsule, spinner, waveform, `Loading model...` |
| `.recording` | `.listening` | Visible capsule, red pulsing dot, live waveform, `Listening...` |
| `.processing` | `.processing` | Visible capsule, spinner, dimmed waveform, `Processing...` |
| `.injecting` | `.processing` | Same Processing presentation; injection is intentionally not shown as Done yet |
| `.completed` | `.done` | Green checkmark, `Done!`, visible for about 400 ms then hidden |
| `.error(error)` | `.error(error)` | Orange warning, mapped short error message, visible until core recovery reaches `.idle` |

A new state cancels a stale completion presentation. In particular, a new recording or error must prevent an old 400 ms Done fade-out from hiding the new state. If the overlay preference becomes false at any point, the controller cancels pending overlay tasks, hides the model, and hides the panel.

Core error recovery remains owned by `AppStateManager`; the overlay does not independently force `.idle` after an error.

## 5. Visual implementation

`RecordingOverlayView` renders one visible 252×48 pt capsule inside a transparent 270×58 pt panel. The capsule has horizontal padding of 12 pt, spacing of 9 pt, and a black fill at approximately 0.84 opacity. It has no explicit border or shadow. The content uses white/off-white SF Pro text at approximately 12.5 pt medium weight.

Listening uses a 10 pt red circle with a 0.9↔1.0 scale pulse over a 0.75 second ease-in-out repeat. Preparing and processing use a small white `ProgressView`. Done uses a green `checkmark.circle.fill`; errors use an orange `exclamationmark.triangle.fill`.

The capsule transitions with opacity and a scale from 0.9 to 1.0 over approximately 180 ms. Hiding uses the controller’s 150 ms ease-in fade. The implementation must preserve the single-surface appearance and must not reintroduce a panel shadow, outer gray shape, border, or separate backing layer.

`WaveformView` renders twelve deterministic capsule bars in an 84×20 pt region. Bar heights range from 3 to 18 pt and derive from the clamped audio level multiplied by fixed per-bar variations. Processing dims the bars to approximately 0.34 opacity; listening/preparing uses approximately 0.86 opacity. A spring animation with response 0.15 and damping fraction 0.6 smooths level changes. The waveform exposes accessibility text with a percentage or `Paused`.

## 6. Menu-bar feedback

`MenuBarController` retains one status item and one transient popover. It polls shared state approximately every 100 ms and updates the status item without changing popover behavior.

The current icon contract is:

| State | Icon behavior |
|---|---|
| `.idle`, `.completed` | Asset-catalog `MenuBarIcon` identity mark, template rendering, 18×18 pt, automatic Light/Dark contrast |
| `.preparingModel` | Animated waveform SF Symbol frames with automatic template tint |
| `.recording` | Red animated microphone SF Symbol frames |
| `.processing`, `.injecting` | Animated waveform SF Symbol frames with automatic template tint |
| `.error` | Orange semantic warning icon |

`MenuBarIcon.imageset/Contents.json` must retain template rendering intent. Idle and completed icons must not hard-code black or white tint: `contentTintColor` remains `nil` so AppKit chooses appropriate contrast in Light and Dark Mode. Recording remains red and error remains orange as semantic colors. The identity icon replacement must not change menu actions, popover presentation, or application lifecycle.

## 7. Settings integration

The overlay reads `VoiceFlowSettingsDefaults.showRecordingOverlay`, default `true`, through `UserDefaults`. General Settings controls this value. Preference changes are observed through `UserDefaults.didChangeNotification` and take effect without restarting the app.

Completion sound is not an overlay responsibility. The injection coordinator owns success-only sound playback, while the overlay owns the visual `.completed` state.

## 8. Tests and verification

The current overlay tests are in `voiceflowTests/UI/RecordingOverlayViewTests.swift`. They verify listening, processing, injecting-as-processing, completed/400 ms hiding, cancellation cleanup, idle hiding, error rendering, focus-safe panel properties, all-Spaces behavior, stale fade-out protection, preference suppression, and audio-level clamping.

Manual visual verification must confirm:

1. TextEdit or another target remains focused while the overlay appears.
2. The panel appears at the bottom center of the active screen and across Spaces.
3. The only visible surface is the single compact black capsule.
4. No gray outer shape, border, native panel shadow, clipping artifact, or backing layer is visible.
5. Listening shows the red pulse and changing waveform; processing dims the waveform and shows a spinner.
6. `.injecting` remains Processing until the actual `.completed` transition.
7. Successful injection shows Done briefly, then hides.
8. Errors show a short actionable message and disappear after core recovery.
9. Disabling the overlay preference suppresses every overlay state.
10. The menu-bar identity icon is sharp and adapts automatically to Light/Dark Mode.

The Specification 04 real TextEdit pipeline test must be rerun after overlay changes to ensure focus and injection remain correct.

## 9. Acceptance criteria

- The overlay is a non-activating, mouse-ignoring floating panel that cannot become key or main.
- The overlay appears across Spaces and is positioned at the bottom-center of the active screen.
- The panel and hosting view are transparent outside the single 252×48 capsule.
- Native panel shadow is disabled; no outer gray or black backing artifact is visible.
- The capsule is compact at approximately 270×58 panel size and 252×48 visible content size.
- All current shared states map to the documented presentation states.
- `.preparingModel` shows `Loading model...`.
- `.processing` and `.injecting` show Processing; only `.completed` shows Done.
- Done remains visible for approximately 400 ms and stale animation tasks cannot hide newer states.
- Errors are rendered with current short messages and core recovery remains centralized.
- Waveform level is clamped and sampled at no more than 30 Hz.
- The overlay preference defaults to true and suppresses the overlay when false.
- Menu-bar identity icon uses a template asset with native Light/Dark contrast.
- Recording and processing/error semantic colors remain unchanged.
- All overlay tests and the core pipeline regression test pass.

## 10. Handoff to Specification 06

Specification 06 may consume `ModelManager`, the existing popover, and the overlay preference contract. It must not replace the status item/popover architecture, alter overlay state timing, or move completion sound ownership into the UI.

## References

[1]: ../voiceflow/UI/Overlay/OverlayWindowController.swift "Overlay window controller"
[2]: ../voiceflow/UI/Overlay/RecordingOverlayView.swift "Overlay model and view"
[3]: ../voiceflow/UI/Overlay/WaveformView.swift "Waveform view"
[4]: ../voiceflow/UI/MenuBar/MenuBarController.swift "Menu-bar controller"
[5]: ../voiceflow/UI/Popover/MenuBarPopoverView.swift "Menu-bar popover"
[6]: ../voiceflowTests/UI/RecordingOverlayViewTests.swift "Overlay tests"
[7]: ../voiceflow/Core/State/AppState.swift "Shared application states"
[8]: ../voiceflow/Core/Injection/InjectionCoordinator.swift "Completion state and sound ownership"
[9]: ../voiceflow/Assets.xcassets/MenuBarIcon.imageset/Contents.json "Template icon asset configuration"

## Implementation inconsistency register

The historical specification required a larger material capsule, border, soft panel shadow, and a Done presentation for `.injecting`. The current implementation intentionally uses a smaller single black capsule, no panel shadow/border, renders `.injecting` as Processing, and renders Done only for `.completed`. The earlier static microphone idle icon requirement is superseded by the VoiceFlow template identity asset.

## Completion gate

Do not begin Specification 06 until overlay tests pass, manual focus/visual checks pass, the core pipeline still injects into TextEdit, and menu-bar template behavior is verified in both Light and Dark Mode.

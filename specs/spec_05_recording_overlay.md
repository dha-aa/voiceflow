# SPEC 05 — Recording Overlay & Menu Bar UI

## 1. Purpose

The core VoiceFlow pipeline (Specs 01–04) is now complete and verified. The user can hold `Fn`, speak, release it, and see transcribed text appear in the focused application — all working correctly.

This specification adds the visual layer: the floating recording overlay and the fully animated menu bar icon. The UI is a pure observer of the already-working core. It does not change, control, or break the pipeline.

The overlay tells the user:
1. **Am I recording?** (Listening state with waveform)
2. **Am I processing?** (Processing state with spinner)
3. **Did my text get inserted?** (Done state, briefly)

---

## 2. Scope

- Implement the floating recording overlay window (pill-shaped, bottom-center of screen).
- Implement overlay state transitions: Listening → Processing → Done → Hidden.
- Implement the live waveform visualizer driven by `AudioRecorder.audioLevel`.
- Implement the recording indicator pulse animation.
- Implement the processing spinner animation.
- Implement the success ("Done!") and error states.
- Implement animated menu bar icon updates (recording pulse, processing animation).
- Ensure the overlay never steals focus from the user's active application.

---

## 3. Out of Scope

Do NOT implement any of the following in this specification:

- Settings window (Spec 06).
- Model management UI (Spec 06).
- Any changes to Core pipeline components.
- Changes to `AppState`, `AppStateManager`, `RecordingCoordinator`, `TranscriptionEngine`, or `TextInjector`.
- Any new business logic — this spec is UI only.

---

## 4. Dependencies

**Specs 01, 02, 03, and 04 must be complete and verified before starting this spec.**

**The Core Pipeline Verification Gate from Spec 04 must have passed.**

Required from Spec 01:
- `AppStateManager` — observable state; overlay observes `currentState`.
- `AppState` — enum cases drive overlay rendering.
- `MenuBarController` — icon update logic already implemented; this spec adds animation.

Required from Spec 02:
- `AudioRecorder.audioLevel: Float` — exposed, updates continuously during recording; the waveform visualizer reads this.

No new framework dependencies required. Use SwiftUI + AppKit for the overlay window.

---

## 5. Implementation Requirements

### 5.1 Overlay Window

Implement `OverlayWindowController` in `UI/Overlay/OverlayWindowController.swift`.

The overlay window must:
- Use `NSPanel` (not `NSWindow`) with `NSPanel.StyleMask` that includes `.nonactivatingPanel` — this prevents the overlay from taking keyboard focus.
- Set `isFloatingPanel = true` so it stays above all other windows.
- Set `level = .floating` or `.statusBar`.
- Set `collectionBehavior = [.canJoinAllSpaces, .stationary]` so it appears on all macOS Spaces.
- Be positioned at the **bottom-center** of the main screen.
- Have a transparent background (`backgroundColor = .clear`, `isOpaque = false`).
- Have `hasShadow = true`.

The overlay must never appear in Exposé/Mission Control as a separate window the user needs to manage.

### 5.2 Overlay SwiftUI View

Implement `RecordingOverlayView` in `UI/Overlay/RecordingOverlayView.swift`.

Visual specifications:
- **Shape:** Rounded pill (capsule), approximately 280–320 pt wide, 52–60 pt tall.
- **Background:** Dark translucent material — use SwiftUI `.ultraThinMaterial` or `.regularMaterial` with a dark appearance override.
- **Border:** Subtle 0.5–1 pt border with a slightly lighter translucent color.
- **Shadow:** Soft, medium radius shadow.
- **Typography:** SF Pro, white or off-white.

Layout (horizontal, left to right):

```
[ ◉ indicator ]  [ ~~~~ waveform ~~~~ ]  [ "Listening..." label ]
```

#### States

**Listening state** (AppState == .recording):
- Left: Red filled circle `◉` with a subtle pulse animation (scale 0.9↔1.0, period ~1.5s).
- Center: Live waveform bars driven by `AudioRecorder.audioLevel`.
- Right: "Listening..." text.

**Processing state** (AppState == .processing):
- Left: Circular `ProgressView()` spinner (small, white).
- Center: Static waveform bars (frozen at last audio level, dimmed).
- Right: "Processing..." text.

**Done state** (brief, ~400ms):
- Left: Green checkmark `✓` (SF Symbol: `checkmark.circle.fill`).
- Center: Empty.
- Right: "Done!" text.
- Automatically transitions to hidden after 400ms.

**Error state** (AppState == .error):
- Left: Yellow/orange warning icon (SF Symbol: `exclamationmark.triangle.fill`).
- Center: Empty.
- Right: Short error description (e.g., "No audio detected", "Model not loaded").
- Stays visible for ~2 seconds then hides.

**Hidden state** (AppState == .idle):
- Overlay is not visible.

#### Animations

**Appear:** Fade in + scale from 0.9 → 1.0, duration 150–200ms, `easeOut`.

**Disappear:** Fade out + scale to 0.95, duration 150ms, `easeIn`.

**State transitions:** Cross-fade between state content, duration 150ms.

**Waveform:** Smooth, continuous updates. Do not update more frequently than 30fps to avoid excessive CPU use.

### 5.3 Waveform Visualizer

Implement `WaveformView` in `UI/Overlay/WaveformView.swift`.

The waveform is a row of vertical bars (approximately 12–16 bars) that respond to `AudioRecorder.audioLevel`.

Behavior:
- Each bar has a height proportional to `audioLevel` with slight random variation between bars to simulate a natural waveform.
- When `audioLevel` is 0.0 (silence), bars shrink to a minimum height (e.g., 4pt).
- When `audioLevel` is 1.0, bars expand to maximum height (e.g., 24pt).
- Use `withAnimation(.spring(response: 0.15, dampingFraction: 0.6))` for smooth bar height updates.
- Bar color: white or off-white, with reduced opacity at minimum height.

```swift
struct WaveformView: View {
    let audioLevel: Float
    // ...
}
```

### 5.4 Overlay Visibility Logic

`OverlayWindowController` must observe `AppStateManager.currentState` and show/hide the overlay, but it must ALSO respect the user's preference to show the overlay at all.

- Read from `UserDefaults.standard.bool(forKey: "showRecordingOverlay")` (default: `true`).
- If this value is `false`, the overlay should never be shown, regardless of `AppState`.

```swift
var interactionTask: Task<Void, Never>?

func updateOverlay(for state: AppState) {
    // Cancel any pending UI delay tasks from previous states to prevent race conditions
    interactionTask?.cancel()

    // Check if the user has disabled the overlay entirely
    let showOverlaySetting = UserDefaults.standard.object(forKey: "showRecordingOverlay") as? Bool ?? true
    if !showOverlaySetting {
        hideOverlay()
        return
    }

    switch state {
    case .idle:
        // Core pipeline often transitions to .idle instantly after .injecting.
        // We must not hide the overlay if it is currently displaying the "Done!" state.
        // The overlay presentation layer itself controls when to hide after success.
        if !overlayView.isShowingDoneState {
            hideOverlay()
        }
    case .recording:
        showOverlay()
        overlayView.showListeningState()
    case .processing:
        overlayView.showProcessingState()
    case .injecting:
        overlayView.showDoneState()
        // The UI owns the duration of the "Done!" state.
        // Auto-hide after 400ms unless a new interaction cancels this task.
        interactionTask = Task {
            defer {
                // Guaranteed cleanup on cancellation or completion
                // Cancelling an overlay interaction task must never leave stale UI state behind.
                overlayView.resetDoneState()
            }
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            hideOverlay()
        }
    case .error(let error):
        overlayView.showErrorState(error)
        // Core state recovery is owned by the core state machine (AppStateManager).
        // UI components must not independently reproduce core lifecycle timers.
        // The overlay will hide when AppStateManager transitions to .idle.
    }
}
```

### 5.5 Animated Menu Bar Icon

Extend `MenuBarController` to add animations for active states.

- `.recording`: Pulse the icon using a `Timer`-based image swap or a small CAAnimation on the status item button.
- `.processing`: Rotate or cycle through waveform frames to suggest activity.
- `.idle`: Return to static icon immediately.

Keep animation lightweight — the menu bar icon is small and animations should not impact battery life. A simple 0.5s crossfade or two-frame pulse is sufficient.

---

## 6. Files and Components

### Files to create

| File | Purpose |
|------|---------|
| `UI/Overlay/OverlayWindowController.swift` | `NSPanel` management, positioning, show/hide |
| `UI/Overlay/RecordingOverlayView.swift` | SwiftUI overlay content with state-based layout |
| `UI/Overlay/WaveformView.swift` | Live waveform bar visualizer |

### Files that may be modified

| File | Permitted change |
|------|----------------|
| `UI/MenuBar/MenuBarController.swift` | Add animated icon states |
| `App/VoiceFlowApp.swift` | Instantiate `OverlayWindowController` |
| `App/AppDelegate.swift` | Same |

### Files that must NOT be modified

| File | Reason |
|------|--------|
| `Core/State/AppState.swift` | Stable from Spec 01 |
| `Core/State/AppStateManager.swift` | Stable from Spec 01 |
| `Core/Audio/` | Stable from Spec 02 |
| `Core/Transcription/` | Stable from Spec 03 |
| `Core/Injection/` | Stable from Spec 04 |

### Reserved (do not create yet)

- `UI/Settings/` — Spec 06

---

## 7. Tests

### Unit Tests: `RecordingOverlayViewTests.swift`

```
test_overlayView_showsListeningState_whenRecording
  Set AppStateManager.currentState = .recording.
  Assert overlay is visible and shows "Listening..." text.

test_overlayView_showsProcessingState_whenProcessing
  Set AppStateManager.currentState = .processing.
  Assert overlay shows "Processing..." text and spinner.

test_overlayView_showsDoneState_whenInjecting
  Set AppStateManager.currentState = .injecting.
  Assert overlay shows "Done!".
  Set AppStateManager.currentState = .idle immediately.
  Assert overlay remains visible showing "Done!" for approximately 400ms, then hides.
  (Validates that UI timing is independent of core state machine rapid transitions)

test_overlayView_cancellation_cleansUpDoneState
  1. Set AppStateManager.currentState = .injecting (Starts Interaction A 400ms timer)
  2. Immediately set AppStateManager.currentState = .recording (Interaction B starts)
  3. Assert Interaction A task is cancelled and visual state is cleaned up (isShowingDoneState = false)
  4. Assert Interaction B overlay remains active in Listening state

test_overlayView_hidden_whenIdle
  Ensure overlay is not in the "Done!" state.
  Set AppStateManager.currentState = .idle.
  Assert overlay is not visible.

test_overlayView_showsError_withDescription
  Set AppStateManager.currentState = .error(.transcriptionFailed).
  Assert overlay shows an error indicator.
```

### UI Tests / Manual Visual Verification

```
test_overlay_doesNotStealFocus
  1. Open TextEdit. Click in the text area.
  2. Hold Fn. Observe overlay appears.
  3. Confirm cursor remains active in TextEdit (can still type).
  4. Release Fn.
  5. Confirm text injection still works (focus was not stolen).

test_overlay_appearsAtBottomCenter
  Hold Fn. Observe overlay appears at bottom-center of the main screen.
  Confirm it is not cut off by the Dock.

test_waveform_respondsToAudioLevel
  Hold Fn. Speak loudly — observe waveform bars grow.
  Be silent — observe waveform bars shrink.
  Confirm smooth animation, no jarring jumps.

test_overlay_animatesIn_andOut
  Hold Fn. Observe fade-in and scale animation (~150ms).
  Release Fn. Wait for processing. Observe Done state.
  Observe overlay fades out.

test_overlayVisibleOnAllSpaces
  Set up two macOS Spaces.
  Hold Fn from Space 1. Overlay appears.
  Switch to Space 2. Confirm overlay is still visible.
```

### Regression: Core Pipeline Must Still Work

```
After adding the overlay, re-run the manual push-to-talk test from Spec 04:
- Hold Fn → speak → release → text injected into TextEdit.
- Confirm the pipeline still works correctly with the overlay present.
- Confirm no regressions in injection accuracy or timing.
```

---

## 8. Acceptance Criteria

All of the following must be true before this spec is complete:

- [ ] Overlay appears when `Fn` is held and disappears when pipeline completes.
- [ ] Overlay does NOT steal keyboard focus from the user's active application.
- [ ] Overlay shows correct state for each `AppState`: Listening, Processing, Done, Error.
- [ ] Waveform responds visibly to microphone audio level.
- [ ] "Done!" state auto-hides after ~400ms.
- [ ] Error state auto-hides after ~2 seconds.
- [ ] Overlay is positioned at bottom-center of the main screen.
- [ ] Overlay appears on all macOS Spaces.
- [ ] Menu bar icon animates during `.recording` and `.processing`.
- [ ] All overlay unit tests pass.
- [ ] Core pipeline still works end-to-end after adding the overlay (regression check).
- [ ] Visual appearance matches the design: pill shape, dark translucent material, smooth animations.

---

## 9. Completion Gate

**This spec is NOT complete until:**

1. All acceptance criteria are checked off.
2. Overlay unit tests pass.
3. Manual visual verification is complete.
4. Core pipeline regression test passes — injection still works with overlay present.
5. No focus-stealing or keyboard interference observed.

**Do not proceed to Spec 06 until this gate passes.**

---

## 10. Handoff to Spec 06

Spec 06 receives a fully working application with a polished UI overlay.

| Component | What Spec 06 can rely on |
|-----------|--------------------------|
| Full pipeline | Core pipeline proven, overlay working |
| `AppStateManager` | Drives all UI states — stable |
| `OverlayWindowController` | Stable show/hide interface |
| `ModelManager` | Stable model list — Settings UI will display and control it |
| `MenuBarController` | Popover showing placeholder "Settings" button |

Spec 06 will implement the Settings window and the model management UI, replacing the placeholder "Settings" button in the popover with a real functional window.

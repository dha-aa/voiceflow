# SPEC 01 — Core Foundation & Application Architecture

## 1. Purpose

This is the first stage of the VoiceFlow project.

VoiceFlow is a macOS menu bar application that lets users dictate text into any focused application by holding the `Fn` key, speaking, and releasing it. The transcribed text is then injected automatically into the focused text field.

This specification establishes the Xcode project, Swift Package Manager dependencies, app entry point, menu bar infrastructure, and the app-level state machine. Every subsequent specification depends on this foundation.

This stage produces no visible recording, transcription, or injection functionality. It only builds the structural skeleton that later specs will fill in.

---

## 2. Scope

- Create the Xcode project as a macOS menu bar app (`LSUIElement`, no Dock icon).
- Configure Swift Package Manager to include the `argmax-oss-swift` package with the `WhisperKit` product.
- Define the `AppState` enum covering all application states.
- Implement `AppStateManager` as an observable state container that publishes the current state.
- Implement the menu bar icon that reflects idle/recording/processing states with static icons (no animation yet).
- Implement a minimal menu bar popover with placeholder content.
- Implement application lifecycle: launch, background operation, quit.
- Establish the project folder structure and file naming conventions used by all subsequent specs.

---

## 3. Out of Scope

Do NOT implement any of the following in this specification:

- Microphone access or audio recording.
- WhisperKit model loading or transcription.
- `Fn` key detection or any global key monitoring.
- The recording overlay window.
- Text injection into other applications.
- Settings window or model management UI.
- Any network requests or model downloading.
- Menu bar icon animations.

---

## 4. Dependencies

**Previous specifications:** None. This is the first specification.

**External dependencies:**
- macOS 14.0 or later.
- Xcode 16.0 or later.
- `argmax-oss-swift` package: `https://github.com/argmaxinc/argmax-oss-swift.git` (version `0.9.0` or later).
- Link only the `WhisperKit` product (not TTSKit or SpeakerKit).

**Assumptions:**
- Xcode and the developer toolchain are already installed.
- The developer has a valid Apple Developer account (required for microphone entitlements in later specs).

---

## 5. Implementation Requirements

### 5.1 Xcode Project Setup

- Create a new macOS App project named `VoiceFlow`.
- Set the deployment target to macOS 14.0.
- Configure `Info.plist`:
  - `LSUIElement = YES` — app runs as a menu bar agent with no Dock icon and no application menu bar.
  - `NSMicrophoneUsageDescription = "VoiceFlow needs microphone access to transcribe your voice."` — required before microphone is accessed in Spec 02.
- Add Hardened Runtime entitlement: `com.apple.security.device.audio-input = YES`.
- Add Swift Package dependency: `https://github.com/argmaxinc/argmax-oss-swift.git` from version `0.9.0`.
- Link the `WhisperKit` product to the app target.

### 5.2 Application State

Define `AppState` as a Swift enum:

```swift
enum AppState: Equatable {
    case idle
    case recording
    case processing
    case injecting
    case error(AppError)
}
```

Define `AppError`:

```swift
enum AppError: Error, Equatable {
    case microphoneUnavailable
    case noAudioDetected
    case modelNotInstalled
    case modelFailedToLoad
    case transcriptionFailed
    case injectionFailed
}
```

Implement `AppStateManager` as an `@Observable` class:

```swift
@Observable
final class AppStateManager {
    private(set) var currentState: AppState = .idle
    private var recoveryTask: Task<Void, Never>?

    func transition(to newState: AppState) {
        // Cancel any pending recovery task when state changes
        recoveryTask?.cancel()
        
        // Log the transition
        // Update currentState
        
        // Centralized Error Recovery:
        // If state is .error, automatically transition back to .idle after 2 seconds
        if case .error = newState {
            recoveryTask = Task {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self.transition(to: .idle)
            }
        }
    }
}
```

Valid forward transitions:
`idle → recording → processing → injecting → idle`

Any state may transition to `.error(...)`.
`.error(...)` must automatically transition to `.idle` after 2 seconds via the centralized recovery mechanism in `AppStateManager`. This is the sole authority for recovering the core state.

Log every state transition using `os.Logger` or `print` for debugging in later specs.

### 5.3 Menu Bar Infrastructure

- Instantiate one `NSStatusItem` at app launch. It must persist for the application lifetime.
- Display an SF Symbol icon in the menu bar based on `AppState`:
  - `.idle` → `"mic"` (static, no animation)
  - `.recording` → `"mic.fill"` (static icon with red tint; animation added in Spec 05)
  - `.processing` → `"waveform"` (static; animation added in Spec 05)
  - `.error` → `"exclamationmark.triangle"`
- Clicking the icon toggles the popover. Do NOT use a standard `NSMenu`.
- The `MenuBarController` must observe `AppStateManager` and update the icon when state changes.

### 5.4 Minimal Menu Bar Popover

Attach an `NSPopover` to the `NSStatusItem`. 

- Create `MenuBarPopoverView` as a SwiftUI view.
- In this specification, it only needs minimal placeholder content:
  - App name ("VoiceFlow").
  - Status text driven by `AppStateManager.currentState` (e.g., "Ready", "Listening", "Processing", "Injecting", "Error").
  - A "Quit VoiceFlow" button that calls `NSApplication.shared.terminate(nil)`.
- Configure the `NSPopover` to display this view.
- Set `NSPopover.behavior = .transient`.
- The `MenuBarController` must handle toggling the popover when the menu bar icon is clicked.

The full settings and model management UI will be added to this popover in Spec 06. The container architecture must be established now and remain stable.

### 5.5 Application Entry Point

- Use `@main` with a SwiftUI `App` struct or an `AppDelegate` — whichever integrates more cleanly with `NSStatusItem` lifecycle.
- The app must not present any windows on launch.
- The app must not appear in the Dock.
- `AppStateManager` must be instantiated once at launch and passed to all components that need it (via dependency injection or SwiftUI environment).

### 5.6 Project Folder Structure

All subsequent specs must place files in the correct location. Establish this structure now (create empty placeholder directories as needed):

```
VoiceFlow/
├── App/
│   ├── VoiceFlowApp.swift          ← @main entry point
│   └── AppDelegate.swift           ← (if using AppDelegate pattern)
├── Core/
│   ├── State/
│   │   ├── AppState.swift          ← AppState + AppError enums
│   │   └── AppStateManager.swift   ← Observable state manager
│   ├── Audio/                      ← reserved for Spec 02
│   ├── Transcription/              ← reserved for Spec 03
│   └── Injection/                  ← reserved for Spec 04
├── UI/
│   ├── MenuBar/
│   │   └── MenuBarController.swift ← NSStatusItem + icon management
│   ├── Popover/
│   │   └── MenuBarPopoverView.swift ← SwiftUI popover content
│   ├── Overlay/                    ← reserved for Spec 05
│   └── Settings/                   ← reserved for Spec 06
└── Resources/
    └── Info.plist
```

---

## 6. Files and Components

### Files to create

| File | Purpose |
|------|---------|
| `App/VoiceFlowApp.swift` | `@main` entry point |
| `App/AppDelegate.swift` | AppDelegate (if used) |
| `Core/State/AppState.swift` | `AppState` and `AppError` enums |
| `Core/State/AppStateManager.swift` | Observable state manager |
| `UI/MenuBar/MenuBarController.swift` | `NSStatusItem`, icon updates, popover attachment |
| `UI/Popover/MenuBarPopoverView.swift` | SwiftUI popover content (placeholder) |

### Files that must NOT be modified after this spec is complete

- `Core/State/AppState.swift` — This is the contract for all subsequent specs. Shape changes break downstream.
- `Core/State/AppStateManager.swift` — The `transition(to:)` interface must remain stable after Spec 01.

### Do not touch

- `Core/Audio/` — Reserved for Spec 02.
- `Core/Transcription/` — Reserved for Spec 03.
- `Core/Injection/` — Reserved for Spec 04.
- `UI/Overlay/` — Reserved for Spec 05.
- `UI/Settings/` — Reserved for Spec 06.

---

## 7. Tests

Write and run these tests before marking this spec complete. Place them in `VoiceFlowTests/State/AppStateManagerTests.swift`.

### Unit Tests

```
test_initialState_isIdle
  Create AppStateManager. Assert currentState == .idle.

test_transition_idleToRecording
  transition(to: .recording). Assert currentState == .recording.

test_transition_recordingToProcessing
  From .recording, transition(to: .processing). Assert currentState == .processing.

test_transition_processingToInjecting
  From .processing, transition(to: .injecting). Assert currentState == .injecting.

test_transition_injectingToIdle
  From .injecting, transition(to: .idle). Assert currentState == .idle.

test_transition_anyStateToError
  From .recording, transition(to: .error(.transcriptionFailed)).
  Assert currentState == .error(.transcriptionFailed).

test_transition_errorToIdle
  From .error(.transcriptionFailed), transition(to: .idle).
  Assert currentState == .idle.
```

### Build Verification

```
- `import WhisperKit` must compile without errors.
  Add it to at least one source file and confirm no "module not found" errors.
- Zero build errors on a clean build.
```

### Manual Verification

```
- Launch the app.
- Confirm no Dock icon appears.
- Confirm the VoiceFlow icon appears in the menu bar.
- Click the icon. Confirm the popover opens.
- Confirm the popover placeholder content renders correctly (status and Quit button).
- Click "Quit VoiceFlow". Confirm the app terminates.
```

---

## 8. Acceptance Criteria

All of the following must be true before this spec is complete:

- [ ] Project builds with zero errors.
- [ ] `import WhisperKit` compiles — confirms the dependency is linked correctly.
- [ ] App launches without a Dock icon.
- [ ] Menu bar icon appears on launch.
- [ ] Clicking the icon shows the popover.
- [ ] Popover shows status label and Quit button.
- [ ] Clicking Quit terminates the app cleanly.
- [ ] All 7 `AppStateManager` unit tests pass.
- [ ] Folder structure matches §5.6.
- [ ] `Info.plist` has `LSUIElement = YES`, `NSMicrophoneUsageDescription`, and the microphone entitlement.

---

## 9. Completion Gate

**This spec is NOT complete until:**

1. All acceptance criteria are checked off.
2. All unit tests pass with zero failures.
3. The project builds cleanly.
4. `AppState` and `AppStateManager` interfaces are frozen and ready to be consumed by Spec 02.
5. No known errors or test failures remain.

**Do not proceed to Spec 02 until this gate passes.**

---

## 10. Handoff to Spec 02

Spec 02 receives these stable, verified components:

| Component | What Spec 02 can rely on |
|-----------|--------------------------|
| `AppState` | Enum with `.idle`, `.recording`, `.processing`, `.injecting`, `.error` — stable interface |
| `AppStateManager` | `currentState` property + `transition(to:)` method |
| `MenuBarController` | Icon updates when `AppStateManager` state changes |
| Project structure | `Core/Audio/` directory ready for Spec 02 audio files |
| Build | App builds and runs; WhisperKit is linked and importable |

Spec 02 will add microphone capture into `Core/Audio/`, and call `transition(to: .recording)` when capture starts and `transition(to: .processing)` when it stops.

# SPEC 01 — Foundation, Application Architecture, and Shared State

## Status and authority

This document is the first stage in the VoiceFlow engineering sequence and defines the contracts consumed by Specifications 02–07. It describes the **current implementation**, not the historical bootstrap requirements. Later specifications may extend the contracts documented here, but they must not silently contradict them.

VoiceFlow is a native macOS menu-bar agent. The user holds `Fn`, speaks into a local microphone recording, releases `Fn`, and receives locally transcribed text in the application that was focused when the hold began. The application has no normal launch window and does not appear in the Dock. Its primary surfaces are the menu-bar status item, a transient popover, a non-activating recording overlay, and an on-demand Settings window. [1] [2]

## 1. Goals

The foundation must provide a stable macOS application shell, dependency injection boundary, shared state model, menu-bar infrastructure, privacy-safe logging categories, and a predictable lifecycle. It must be possible for later stages to add recording, model loading, injection, overlay, Settings, and release automation without recreating the application shell.

The foundation does **not** by itself perform recording, model loading, transcription, text injection, overlay presentation, or model management. Those behaviors are defined in Specifications 02–07, although the current application composition wires all completed components together at launch.

## 2. Dependency and implementation baseline

| Item | Current contract |
|---|---|
| Platform | macOS 14.0 or later |
| Language/toolchain | Swift 5 language mode; development and CI use Xcode, with CI selecting Xcode 16.4 on `macos-15` runners |
| Application target | Xcode target `voiceflow`, product `VoiceFlow.app`, bundle identifier `dha-aa.voiceflow` |
| Test target | `voiceflowTests`, importing the application module as `voiceflow` |
| Package dependency | `argmaxinc/argmax-oss-swift`, resolved at version 0.18.0; the app uses the `WhisperKit` product |
| Application type | `LSUIElement = true`; no Dock icon and no launch window |
| Bundle metadata | `CFBundleName = VoiceFlow`; version and build are supplied by `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` |
| Privacy baseline | Audio and dictated/transcribed content remain local and must never be logged |

The package resolution is part of the repository contract and is recorded in `voiceflow.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`. [3]

## 3. Application composition

`VoiceFlowApp` is the SwiftUI `@main` entry point and installs `AppDelegate` through `@NSApplicationDelegateAdaptor`. It declares no SwiftUI scene because VoiceFlow is a menu-bar application. `AppDelegate.applicationDidFinishLaunching` creates one shared `AppStateManager`, then constructs and retains the menu-bar controller, model manager, transcription engine/coordinator, injection coordinator, audio recorder, recording coordinator, and overlay controller. [4] [5]

The composition root owns dependency wiring. The important runtime relationships are:

```text
AppDelegate
├── AppStateManager
├── MenuBarController ── observes state, owns NSStatusItem + NSPopover
├── ModelManager ─────── owns local WhisperKit catalog/model lifecycle
├── TranscriptionEngine ── loads/caches WhisperKit sessions
├── TranscriptionCoordinator ── audio URL → processed text
├── InjectionCoordinator ── processed text → target application
├── AudioRecorder
├── RecordingCoordinator ── Fn events + recorder + readiness gate
└── OverlayWindowController ── observes state and audio level
```

The application starts the recording and overlay controllers during launch. It also refreshes the model catalog and requests background preload of the persisted selected model. A `--model-preflight --model-id <id>` launch mode prints a metadata-only preflight report and exits; it does not print audio or text content. [4] [6]

On termination, the AppDelegate stops the recording and overlay controllers and releases the owned coordinators. The application does not terminate merely because a Settings window closes. [4]

## 4. Shared state model

`AppState` is the shared lifecycle enum:

```swift
enum AppState: Equatable {
    case idle
    case preparingModel
    case recording
    case processing
    case injecting
    case completed
    case error(AppError)
}
```

`AppError` currently contains:

```swift
enum AppError: Error, Equatable {
    case microphoneUnavailable
    case noAudioDetected
    case modelNotInstalled
    case modelFailedToLoad
    case transcriptionFailed
    case injectionFailed
    case accessibilityPermissionDenied
}
```

`AppStateManager` is an `@Observable` reference type with a private-set `currentState`, initially `.idle`, and a stable `transition(to:)` method. Every transition cancels any pending recovery task, updates the state, and prints a diagnostic transition line. When the new state is `.error`, the manager schedules recovery to `.idle` after two seconds unless another transition or cancellation intervenes. [7]

The lifecycle expected by the current implementation is:

```text
idle
  └─ Fn hold → preparingModel → recording
recording
  └─ Fn release → processing
processing
  └─ successful transcription → injecting
injecting
  └─ successful injection → completed → idle after about 400 ms
any active stage
  └─ failure → error(AppError) → idle after about 2 s
```

A release before permission or model readiness completes is a normal cancelled startup and returns to `.idle`; it is not a transcription or microphone error. Requests received outside the stage that owns them are ignored by the relevant coordinator. The state manager is the authority for core error recovery; UI controllers must not create competing recovery timers. [7] [8] [9]

### Architectural note

The state manager currently uses `print` for transition diagnostics while the rest of the production pipeline also has privacy-safe `OSLog` categories. This is a known production-cleanup gap, not permission to log user content. A future hardening change should replace remaining diagnostic `print` calls with structured, content-free logging without changing the public state contract.

## 5. Menu-bar infrastructure

`MenuBarController` creates exactly one persistent `NSStatusItem` and one transient `NSPopover`. The popover hosts `MenuBarPopoverView` through an `NSHostingController`; it is not an `NSMenu`. Clicking the status item toggles the popover. The controller observes state by polling on the main run loop at approximately 100 ms and updates the status icon. [10]

The current icon behavior is:

| State | Current presentation |
|---|---|
| `.idle`, `.completed` | `MenuBarIcon` asset-catalog image, marked template, 18×18 pt; AppKit derives Light/Dark contrast because no hard-coded tint is applied |
| `.preparingModel` | Animated waveform SF Symbol frames with automatic template tint |
| `.recording` | Red microphone SF Symbol pulse frames |
| `.processing`, `.injecting` | Animated waveform SF Symbol frames with automatic template tint |
| `.error` | Orange `exclamationmark.triangle` semantic icon |

The normal idle icon is the VoiceFlow identity mark stored in `Assets.xcassets/MenuBarIcon.imageset`, not the old microphone glyph. Its catalog rendering intent is `template`, and its light/dark appearance is therefore controlled by native menu-bar rendering. The menu-bar behavior and actions are independent of Settings and must remain stable when the icon asset changes. [10] [11]

`MenuBarPopoverView` displays the app name, a live status label, the selected model display name or `No active model`, a `Settings...` button, and `Quit VoiceFlow`. The status labels are `Ready`, `Done`, `Loading model`, `Listening`, `Processing`, `Injecting`, and `Error`. [12]

## 6. Resources and entitlements

The tracked `voiceflow/Resources/Info.plist` must contain:

| Key | Current value |
|---|---|
| `CFBundleIdentifier` | `$(PRODUCT_BUNDLE_IDENTIFIER)` |
| `CFBundleName` | `VoiceFlow` |
| `CFBundleShortVersionString` | `$(MARKETING_VERSION)` |
| `CFBundleVersion` | `$(CURRENT_PROJECT_VERSION)` |
| `LSUIElement` | `true` |
| `NSHumanReadableCopyright` | `Copyright © 2026 VoiceFlow` |
| `NSMicrophoneUsageDescription` | `VoiceFlow needs microphone access to transcribe your voice.` |

The tracked entitlements file disables App Sandbox and enables microphone input:

```xml
<key>com.apple.security.app-sandbox</key>
<false/>
<key>com.apple.security.device.audio-input</key>
<true/>
```

App Sandbox is disabled because the current global Fn monitoring, Accessibility interaction, and cross-process keyboard event behavior require a non-sandboxed application. [13] [14]

## 7. Testing requirements

Foundation tests must verify the initial state and direct state transitions, including `.idle`, `.recording`, `.processing`, `.injecting`, and `.error`. The current suite is `voiceflowTests/State/AppStateManagerTests.swift`.

Build verification must run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project voiceflow.xcodeproj \
  -scheme voiceflow \
  -configuration Debug \
  -destination 'platform=macOS' \
  ONLY_ACTIVE_ARCH=YES \
  -only-testing:voiceflowTests \
  test CODE_SIGNING_ALLOWED=NO
```

Manual foundation verification must confirm that the application launches without a Dock icon, displays the VoiceFlow menu-bar identity icon, opens the transient popover, displays the live status/model content, and quits from the popover. Full model, recording, injection, overlay, Settings, and release verification belongs to the later specifications.

## 8. Acceptance criteria

- The app target builds as `VoiceFlow.app` with bundle identifier `dha-aa.voiceflow`.
- `WhisperKit` imports successfully from the resolved Swift package.
- The app launches as an `LSUIElement` without a Dock icon or launch window.
- One menu-bar status item and one transient popover are created and retained for the app lifetime.
- The popover uses SwiftUI content and provides Settings and Quit actions.
- `AppStateManager` starts at `.idle` and exposes the stable `transition(to:)` contract.
- The state enum includes `.preparingModel` and `.completed`; error recovery returns to `.idle` after approximately two seconds.
- The menu-bar icon maps to the current state, with the idle/completed VoiceFlow asset rendered as a native template image.
- Privacy-safe logging never includes audio, spoken text, or transcription text.
- All foundation tests pass.

## 9. Handoff to Specification 02

Specification 02 may rely on:

| Component | Handoff contract |
|---|---|
| `AppState` | Current enum including `.preparingModel` and `.completed` |
| `AppStateManager` | `currentState` and `transition(to:)`; centralized error recovery |
| `AppDelegate` | Stable composition root for adding the audio stage |
| `MenuBarController` | Persistent status item and popover; state-driven icon updates |
| Resources | Microphone usage description and audio-input entitlement already present |
| Logging | `VoiceFlowLog.audio`, `.model`, `.transcription`, and `.pipeline` categories are available |

## References

[1]: ../README.md "VoiceFlow project overview"
[2]: ../voiceflow/App/AppDelegate.swift "VoiceFlow application composition"
[3]: ../voiceflow.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved "Resolved Swift package dependencies"
[4]: ../voiceflow/App/AppDelegate.swift "AppDelegate lifecycle and dependency wiring"
[5]: ../voiceflow/App/VoiceFlowApp.swift "SwiftUI application entry point"
[6]: ../voiceflow/Core/Transcription/ModelManager.swift "Model preflight command and model lifecycle"
[7]: ../voiceflow/Core/State/AppState.swift "Shared state and error enums"
[8]: ../voiceflow/Core/Audio/RecordingCoordinator.swift "Recording readiness and state sequencing"
[9]: ../voiceflow/Core/Injection/InjectionCoordinator.swift "Completion and injection state sequencing"
[10]: ../voiceflow/UI/MenuBar/MenuBarController.swift "Status item, popover, and icon behavior"
[11]: ../voiceflow/Assets.xcassets/MenuBarIcon.imageset/Contents.json "Template menu-bar asset configuration"
[12]: ../voiceflow/UI/Popover/MenuBarPopoverView.swift "Current popover content and labels"
[13]: ../voiceflow/Resources/Info.plist "Bundle metadata and microphone usage description"
[14]: ../voiceflow/Resources/voiceflow.entitlements "Current application entitlements"

## Completion gate

Do not begin Specification 02 until the application shell builds, foundation tests pass, the status item/popover are manually verified, and the shared state contract is understood. This gate verifies the foundation; it does not imply that later pipeline stages are complete.

## Implementation inconsistency register

The historical specification froze the state enum before `.preparingModel` and `.completed` existed and required a placeholder microphone icon. Those requirements are intentionally superseded by this document. The current implementation also retains a small amount of `print`-based diagnostics; this is recorded as a cleanup item for Specification 07 rather than silently treated as the final logging design.

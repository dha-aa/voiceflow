# VoiceFlow Architecture Map

## Project purpose

VoiceFlow is a native macOS menu-bar dictation application. The primary workflow is **hold Fn → record locally → release Fn → transcribe locally → process conservatively → inject into the focused application**, with clipboard fallback when no text input is available.

## Runtime entry points

| Entry point | Responsibility |
|---|---|
| `voiceflow/App/VoiceFlowApp.swift` | SwiftUI application declaration. |
| `voiceflow/App/AppDelegate.swift` | macOS lifecycle, startup/shutdown, composition creation, preflight command handling, and pipeline callback wiring. |
| `voiceflow/App/ApplicationComposition.swift` | Owns app-wide services and assembles the runtime graph. |
| `voiceflow/UI/MenuBar/MenuBarController.swift` | Menu-bar item, state observation, template icon, and popover presentation. |
| `voiceflow/UI/Settings/SettingsWindowController.swift` | Settings window lifetime and presentation. |

## Module boundaries

| Module | Location | Owns |
|---|---|---|
| Audio | `voiceflow/Core/Audio/` | Global Fn monitoring, microphone capture, recording coordination, audio-file retention, and cleanup. |
| State | `voiceflow/Core/State/` | Typed application state and state transitions. |
| Transcription | `voiceflow/Core/Transcription/` | Engine-neutral speech contracts, WhisperKit lifecycle, FluidAudio/Parakeet lifecycle, model discovery/validation, and text normalization. |
| LLM | `voiceflow/Core/LLM/` | Provider-neutral AI request contracts, prompt modes, Claude client/catalog, AI settings persistence, and Keychain access boundaries. |
| Injection | `voiceflow/Core/Injection/` | Captured-target metadata, capability inspection, ordered AX/paste/keyboard strategies, terminal paste fallback, clipboard fallback, and completion feedback. |
| Permissions | `voiceflow/Core/Permissions/` | Microphone, Accessibility/Input Monitoring, and screen-context permission status and requests. |
| Logging | `voiceflow/Core/Logging/` | Privacy-safe structured diagnostics. Never log audio, raw transcripts, inserted text, clipboard contents, or secrets. |
| UI | `voiceflow/UI/` | SwiftUI/AppKit presentation only: menu bar, popover, overlay, onboarding, and Settings. UI observes Core state and invokes Core services; it does not duplicate pipeline decisions. |
| Tests | `voiceflowTests/` | Unit, integration, model lifecycle, injection, overlay, onboarding, Settings, and provider regression tests. |

## Main data flow

```text
FnKeyMonitor
    ↓
RecordingCoordinator ──→ AppStateManager (.recording / .processing)
    ↓
AudioRecorder ──→ local WAV file
    ↓
SpeechTranscriptionRouter
    ├── WhisperKit → TranscriptionEngine → ModelManager
    └── FluidAudio → ParakeetTranscriptionEngine → ParakeetModelManager
    ↓
TextProcessor
    ↓
ClaudeCommandProcessor / Grammar Fix / local SnippetStore expansion
    ↓
InjectionCoordinator
    ├── TextInjector → InjectionContext → ordered AX/paste/keyboard strategies
    └── clipboard fallback when no active text field exists
    ↓
completion state and optional completion sound
```

The recording coordinator gates recording on model readiness and captures the target application plus selected text. The transcription coordinator must not inject text itself. The injection coordinator is the only component that reports successful insertion and completion feedback.

## Dependency direction

The allowed direction is intentionally one-way:

```text
App composition → Core services/coordinators → platform/provider adapters
UI views/controllers → Core state and explicit service interfaces
Tests → production protocols and test doubles
```

Core business logic must not import SwiftUI. Provider SDKs and network clients stay behind provider-specific adapters and protocols. AppKit is permitted in the AppKit integration boundaries for global keyboard monitoring, focused-application access, pasteboard/event synthesis, windows, and sound playback. SwiftUI views should receive app-owned service instances explicitly rather than constructing duplicate stores or managers.

## Ownership rules

`ApplicationComposition` owns the long-lived runtime instances, including `ModelDownloadCoordinator` and the app-wide `VoiceFlowPermissionManaging` implementation. `AppDelegate` owns lifecycle start/stop and passes the composition’s instances to UI controllers. The menu-bar controller and popover forward those same instances to `SettingsWindowController`. Settings views receive the same `SnippetStore`, `AudioRetentionManager`, model managers, download coordinator, and permission manager used by the runtime; they must not silently create replacement instances or default-construct services in production paths.

`ModelManager` remains the WhisperKit lifecycle facade. `ModelDownloadCoordinator` is a composition-owned UI-state coordinator around that facade; it is not created by `SettingsWindowController` or a SwiftUI view. Path resolution, model definitions, and preflight validation are pure/supporting concerns and may live in focused files, but download, import, select, delete, and readiness behavior must continue to use one canonical model root. FluidAudio remains a separate provider implementation because its bundle format and validation rules differ from WhisperKit’s.

## Documentation roles

- `README.md` is the user-facing overview, setup guide, privacy summary, and command reference.
- `CONTRIBUTING.md` defines contributor workflow, coding constraints, privacy requirements, and pull-request expectations.
- `docs/architecture.md` is the concise agent-oriented map of modules, ownership, flow, and dependency direction.
- `docs/testing.md` defines automated and manual verification procedures.
- `docs/release.md` defines unsigned/signed release behavior and credentials.
- `specs/` contains the current seven implementation and verification specifications.
- `spec_changes/` is sequential historical change documentation; it is not a replacement for current specifications.

When architecture, APIs, commands, folder structure, workflows, or user-facing behavior changes, update the relevant current documentation and add a historical `spec_changes/` record when the project’s established change-history convention requires one. `ManualFnProbe.swift` and `WhisperProbe.swift` are local-only debugging probes in the current working tree; they are not production targets or supported repository tools. A supported probe must be moved under a documented `tools/probes/` directory in a separate focused change.

## Development commands

Run the full test target:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project voiceflow.xcodeproj -scheme voiceflow -configuration Debug \
  -derivedDataPath /tmp/voiceflow-tests -destination 'platform=macOS' \
  ONLY_ACTIVE_ARCH=YES -only-testing:voiceflowTests test \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Build the local app bundle with `./scripts/buildapp.sh --clean`. The expected artifact is `build/VoiceFlow.app`. Keep build output, Xcode user state, model files, audio files, release artifacts, and credentials out of commits.

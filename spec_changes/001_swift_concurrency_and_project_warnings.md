# Specification Change 001: Swift Concurrency and Project Warning Fixes

**Date:** 2026-08-23
**Status:** Implemented and validated
**Commit:** `ee7bb75 Fix Swift concurrency and project warnings`

## Purpose

This change records the corrections made after the VoiceFlow Xcode project reported actor-isolation diagnostics, an exhaustive-switch warning, an Info.plist resource warning, a sandbox-setting mismatch, and an AppIcon asset warning.

The implementation preserves the existing local audio → WhisperKit → text-injection pipeline, overlay behavior, menu-bar behavior, settings behavior, and privacy rules. No microphone audio, transcript text, injected text, clipboard content, or credentials were added to diagnostics.

## Scope

The following source and project files were changed:

| Path | Change |
|---|---|
| `voiceflow/Core/Logging/VoiceFlowLogger.swift` | Marked the pure `audioIdentifier(for:)` helper `nonisolated`. |
| `voiceflow/Core/Transcription/TranscriptionEngine.swift` | Removed the actor-isolated default factory argument and added explicit initializer overloads. |
| `voiceflow/UI/MenuBar/MenuBarController.swift` | Hopped timer callback work to `@MainActor`. |
| `voiceflow/UI/Overlay/OverlayWindowController.swift` | Hopped notification, timer, and animation-completion callback work to `@MainActor`. |
| `voiceflow/UI/Settings/GeneralSettingsView.swift` | Added the explicit `.notFound` `SMAppService.Status` case. |
| `voiceflow.xcodeproj/project.pbxproj` | Excluded `Resources/Info.plist` from synchronized resource membership and aligned Debug sandbox settings. |
| `voiceflow/Assets.xcassets/AppIcon.appiconset/Contents.json` | Declared the supported classic macOS icon slots only. |
| `voiceflow/Assets.xcassets/AppIcon.appiconset/dark-*.png` | Removed unsupported/orphaned dark-appearance children from the classic macOS AppIcon set. |

Unrelated Xcode user state and diagnostic probes were intentionally left outside the change.

## Detailed changes

### Audio recording logging isolation

The `AudioRecorder` diagnostic was caused by `VoiceFlowLog.audioIdentifier(for:)` being inferred as main-actor isolated even though it only derives a string from a URL. The helper is now explicitly `nonisolated`.

This keeps the audio engine callback nonisolated and avoids introducing a main-actor hop into real-time audio processing. The recorder’s capture, conversion, file-writing, metrics, and audio-level behavior are unchanged.

### Transcription engine initialization

`TranscriptionEngine` remains `@MainActor` because it owns model selection, readiness, cached sessions, and preload state. The previous default parameter constructed `LiveWhisperKitSessionFactory()` from a synchronous initializer declaration context and produced a main-actor isolation diagnostic.

The production initializer now constructs the live factory inside the main-actor initializer body. A second initializer accepts an explicit `WhisperKitSessionFactory` for tests and dependency injection. Model loading, session reuse, preload behavior, and transcription behavior are unchanged.

### Menu-bar timer callbacks

`MenuBarController` remains `@MainActor`. The state-observation timer and both icon-animation timers now wrap their callback bodies in:

```swift
Task { @MainActor [weak self] in
    // Main-actor-owned state and AppKit UI work.
}
```

`lastState` is read and mutated only inside the main-actor task. `animationFrame` is toggled only inside the main-actor task. `updateIcon(for:)` and `setIcon(...)` are also called only inside the main-actor task. This is an actor-correctness fix, not warning suppression, and does not change the timer intervals or icon states.

### Overlay timer and callback isolation

`OverlayWindowController` remains `@MainActor`. The following callbacks now explicitly hop to the main actor:

- the `UserDefaults` change observer;
- the state-observation timer;
- the 30 Hz audio-level sampling timer; and
- the panel animation completion handler.

As a result, `lastObservedState`, `audioRecorder`, `overlayModel`, and `panelAnimationGeneration` are accessed only in their owning actor context. Overlay visibility, Done-state timing, animation generation checks, and waveform sampling behavior are unchanged.

### General settings switch

The launch-at-login status switch now handles all currently known `SMAppService.Status` cases:

```swift
case .enabled:
case .requiresApproval:
case .notRegistered:
case .notFound:
@unknown default:
```

`.notFound` displays an explicit unavailable-installation message. `@unknown default` remains to preserve forward compatibility with future SDK cases.

## Project configuration changes

### Info.plist resource membership

The project uses an Xcode file-system-synchronized source group. `Resources/Info.plist` was excluded using a `PBXFileSystemSynchronizedBuildFileExceptionSet` for the `voiceflow` target.

The file remains configured through:

```text
INFOPLIST_FILE = voiceflow/Resources/Info.plist
```

Therefore Xcode still processes it as the application property list, but it is no longer treated as an ordinary resource in Copy Bundle Resources.

### App Sandbox consistency

Both Debug and Release now use:

```text
ENABLE_APP_SANDBOX = NO
```

This matches `voiceflow/Resources/voiceflow.entitlements`, where `com.apple.security.app-sandbox` is `false`.

The non-sandboxed configuration is intentional for the current architecture because VoiceFlow uses global Fn monitoring and cross-process Accessibility text injection in addition to microphone recording. The application’s existing Hardened Runtime and microphone-entitlement behavior were not otherwise changed.

### AppIcon asset assignments

The classic macOS AppIcon set now declares all ten required slots:

| Point size | 1x | 2x |
|---|---|---|
| 16x16 | `light-16-mac.png` | `light-32-mac.png` |
| 32x32 | `light-32-mac.png` | `light-64-mac.png` |
| 128x128 | `light-128-mac.png` | `light-256-mac.png` |
| 256x256 | `light-256-mac.png` | `light-512-mac.png` |
| 512x512 | `light-512-mac.png` | `light-1024-mac.png` |

The ten reported unassigned children were the dark-appearance entries, not missing required macOS sizes. The current `actool` treated those `luminosity=dark` children as unassigned in this classic macOS AppIcon set. Their metadata entries and orphaned PNG files were removed so the asset catalog compiles without the warning.

This is a compatibility decision for the current classic macOS asset-catalog format. If appearance-specific macOS icons are required later, they should be migrated through the macOS Icon Composer workflow rather than reintroducing unsupported `luminosity=dark` children into this AppIcon set.

## Validation

The following checks were completed after the changes:

| Validation | Result |
|---|---|
| Baseline warning reproduction | Confirmed the reported Swift and project warnings before modification. |
| Debug build | Passed. No requested Swift diagnostics remained. |
| Unsigned Release build | Passed. |
| Full XCTest suite | Passed: 102 tests, 0 failures. |
| Info.plist resource warning | Cleared. |
| AppIcon unassigned-child warning | Cleared. |
| Debug/Release sandbox consistency | Both configurations report `ENABLE_APP_SANDBOX = NO`. |
| Git diff validation | Passed with no whitespace errors. |
| Remote synchronization | `origin/main` matches `ee7bb751e614c34f00d44d717b03b9b069ff9997`. |

An unrelated Xcode App Intents metadata warning may still appear because the target has no AppIntents framework dependency. It is not part of this change and does not prevent a successful build.

## References

[1]: https://developer.apple.com/documentation/xcode/configuring-your-app-icon "Apple Developer: Configuring your app icon using an asset catalog"

[2]: https://developer.apple.com/videos/play/wwdc2025/220/ "Apple Developer: Say hello to the new look of app icons — WWDC25"

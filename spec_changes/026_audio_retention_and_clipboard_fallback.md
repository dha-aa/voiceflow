# Change 026: Audio Retention Controls and Clipboard Fallback

## Summary

VoiceFlow now gives users direct control over how long completed recordings remain in the local application audio folder. It also produces useful output when no active text input is available by copying the final transcription to the macOS clipboard instead of treating the operation as an injection failure.

The two behaviors preserve the existing local-first pipeline:

> Fn hold → record locally → release → transcribe locally → optional AI processing → local snippet expansion → inject into a focused text input or copy to the clipboard → show completion feedback

## Audio retention

Recordings continue to be stored as UUID-named WAV files under:

```text
~/Library/Application Support/<bundle identifier>/audio/
```

For the production bundle, this is normally:

```text
~/Library/Application Support/dha-aa.voiceflow/audio/
```

The **General** Settings pane now provides an **Audio** section with the following policies:

| Setting | Behavior |
|---|---|
| Delete instantly | Remove a completed recording as soon as the retention cleanup runs. |
| Delete after 5 hours | Keep the recording for five hours after its file modification time, then remove it. |
| Delete after 3 days | Keep the recording for three days, then remove it. |
| Delete after 7 days | Keep the recording for seven days, then remove it. |
| Never delete | Keep recordings until the user manually deletes them. This is the default. |

The selected policy is persisted in `UserDefaults` using `audioRetentionPolicy`. The default is `.never`, so a fresh installation does not silently delete recordings. VoiceFlow performs cleanup when the app launches, after a transcription completes, when the user changes the retention policy, and periodically while the app is running. The periodic cleanup runs once per hour and does not require a separate background service.

The **Delete All Audio** button in General Settings asks for confirmation, then removes all `.wav` recordings in the managed VoiceFlow audio directory. It does not remove unrelated files in that directory. Deletion failures are logged only as metadata-level error categories.

## Clipboard fallback

The normal output path still attempts text injection when a focused text input is available. `TextInjector` now exposes a lightweight text-input availability check based on the focused Accessibility element. If the captured target application is unavailable, or if the focused element is not a supported text field, text area, search field, combo box, web area, or compatible value/range control, the final output is copied to `NSPasteboard.general`.

The clipboard path is implemented through the `ClipboardWriting` protocol so it can be tested without modifying the real user clipboard. The system implementation replaces the current general clipboard contents with the final text and reports a failure if clearing or writing fails.

Successful clipboard output transitions the application to `.copiedToClipboard`. The overlay displays:

> Copied to Clipboard

and uses a clipboard completion icon before returning to idle. The menu-bar popover also reports **Copied to Clipboard** while that completion state is visible. Normal successful injection continues to use `.completed` and displays **Done!**.

Completion sounds, when enabled, play after either successful text injection or successful clipboard copy. They do not play when transcription, output delivery, or clipboard writing fails.

## Privacy behavior

Audio retention is local file management and does not create a network request. Audio files are not uploaded automatically. Optional Claude processing retains its existing explicit opt-in behavior; stored Snippet values remain local and are expanded after AI processing, so they are not sent to any provider. Diagnostics contain only safe metadata such as state, character counts, file lifecycle categories, and error categories. They do not contain audio contents, transcripts, injected text, clipboard contents, or secrets.

The clipboard fallback intentionally writes the final transcription to the user’s general clipboard because that is the requested user-visible behavior. The clipboard value itself is not logged. Users should remember that other applications may read the general clipboard according to macOS behavior.

## Implementation

| Component | Responsibility |
|---|---|
| `AudioRetentionPolicy` | Defines the five user-selectable retention policies and their intervals. |
| `AudioRetentionManager` | Persists/reads the selected policy, removes expired WAV files, handles periodic cleanup, and deletes all managed recordings on request. |
| `GeneralSettingsView` | Presents the retention picker, local-storage explanation, confirmation dialog, and Delete All Audio action. |
| `TextInputAvailabilityChecking` | Allows the output coordinator to distinguish a usable text input from an unavailable or non-text target. |
| `ClipboardWriting` / `SystemClipboardWriter` | Provides testable clipboard output using `NSPasteboard.general`. |
| `InjectionCoordinator` | Chooses injection or clipboard output, plays enabled completion feedback, and transitions to `.completed` or `.copiedToClipboard`. |
| `AppState.copiedToClipboard` | Represents successful clipboard delivery separately from ordinary text injection. |
| `RecordingOverlayModel` | Presents the Copied to Clipboard status and clipboard icon. |
| `OverlayWindowController` | Shows and fades the clipboard completion state using the existing completion timing. |
| `AppDelegate` | Starts retention cleanup at launch, performs cleanup after transcription, and stops the periodic timer at termination. |

## Acceptance criteria

| Area | Acceptance criterion |
|---|---|
| Policy options | General Settings presents Delete instantly, 5 hours, 3 days, 7 days, and Never delete. |
| Default | A fresh installation defaults to Never delete. |
| Persistence | A selected retention policy survives app relaunch through `UserDefaults`. |
| Expiry | Cleanup removes eligible WAV files based on modification time and leaves recent files untouched. |
| Manual deletion | Delete All Audio removes managed WAV recordings after confirmation and preserves unrelated files. |
| Cleanup lifecycle | Expiry cleanup runs at launch, after transcription, after policy changes, and hourly while the app is running. |
| Normal injection | A valid focused text input continues through the existing Accessibility/keyboard injection path. |
| No target | With no target application, final output is copied to the clipboard and is not sent to the text injector. |
| No text field | With a target application but no supported focused text input, final output is copied to the clipboard. |
| Overlay | Clipboard success displays Copied to Clipboard, then returns to idle using the existing fade timing. |
| Sound | Enabled completion sound plays after successful injection or clipboard copy only. |
| Failure | Clipboard or injection failure transitions to an error and does not play the completion sound. |
| Privacy | No new network request is introduced; audio, transcripts, clipboard values, and snippet values remain absent from logs. |
| Compatibility | Fn push-to-talk, model readiness, local transcription, AI precedence, snippets, selection handling, model management, permissions, and normal injection remain intact. |

## Verification evidence

The test-first sequence added red tests before implementation for retention defaults and persistence, expired-file cleanup, Delete All Audio, no-target clipboard fallback, no-focused-text-input fallback, and the Copied to Clipboard overlay presentation.

The focused validation suite completed with **42 tests and zero failures**. The complete `voiceflowTests` suite completed with **181 tests and zero failures**.

The full validation includes the existing recording, transcription, model, AI, selection, injection, overlay, onboarding, settings, and privacy regressions, plus the new retention and clipboard coverage.

## Known boundary

The retention timer runs while VoiceFlow is open. Launch-time cleanup covers files that expire while the app is not running. VoiceFlow does not attempt to monitor or clear clipboard contents after copying; the final transcription remains in the general clipboard until another application replaces it or the user changes it.

# Specification Change 007 — AI Provider Overlay Status and Stable Settings Toggles

## Summary

VoiceFlow now identifies the active AI provider in the recording overlay and explicitly applies the native macOS switch style to Settings toggles.

## Provider-aware overlay

When the local transcript matches the configured AI prefix and the selected provider is implemented, `TranscriptionCoordinator` emits `onAIProcessingStarted` before awaiting the provider response. `AppDelegate` connects that callback to `OverlayWindowController`, which updates the existing overlay model without creating a second state system.

The overlay displays:

| Pipeline condition | Overlay label |
|---|---|
| Local processing or normal dictation | `Processing...` |
| Claude request in progress | `Using Claude...` |
| Future ChatGPT request | `Using ChatGPT...` |
| Successful injection | `Done!` |

The provider label is metadata only. It does not expose prompts, responses, audio, API keys, or transcript text. The provider context is cleared when the pipeline enters injection, completion, error, or hidden states.

ChatGPT remains a future provider in the current release; its label is supported by the provider-neutral overlay model, but no ChatGPT request path is active.

## Settings toggle stability

`GeneralSettingsView` and `AISettingsView` now apply `.toggleStyle(.switch)` explicitly. This keeps the controls rendered as native macOS switches after the Settings window is closed and reopened, rather than allowing a contextual SwiftUI style to appear as a blue button-like control.

The Settings window continues to use the existing fixed geometry and root-view recreation behavior. No existing preferences or settings actions were removed.

## Tests

Added deterministic coverage for:

- Default local processing label.
- `Using Claude...` status and accessibility label.
- Future `Using ChatGPT...` status support.
- Provider callback delivery from Claude routing before response injection.
- Existing overlay state, animation, focus-safety, and completion behavior.

Manual verification remains required for visual confirmation: open and close Settings several times, visit General and AI, and confirm every toggle remains a native switch. Run a Claude-prefixed request and confirm the overlay shows `Using Claude...` before the response is injected.

## References

- [RecordingOverlayView.swift](../voiceflow/UI/Overlay/RecordingOverlayView.swift)
- [OverlayWindowController.swift](../voiceflow/UI/Overlay/OverlayWindowController.swift)
- [TranscriptionCoordinator.swift](../voiceflow/Core/Transcription/TranscriptionCoordinator.swift)
- [AIProvider settings](../voiceflow/Core/LLM/AISettings.swift)

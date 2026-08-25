# Change 028: Reliable Terminal Paste Fallback

## Summary

The first Terminal-specific keyboard-event routing was not reliable on all macOS environments. VoiceFlow now uses a paste-based output path for supported Terminal-family applications. It temporarily places the final text on the general pasteboard, posts a Command-V event through the frontmost HID event tap, waits briefly for the target terminal to consume the paste, and restores the user’s previous pasteboard contents.

The revised output flow is:

> Capture target application at Fn hold → transcribe/process locally → identify Terminal-family target → temporary clipboard write → frontmost Command-V → restore previous clipboard → show Done

## Terminal output behavior

`TextInjector` classifies supported terminal emulators using their bundle identifier. For Apple Terminal, iTerm2, Alacritty, Ghostty, Kitty, and WezTerm, it routes output to `SystemTerminalTextPaster` before attempting the ordinary Accessibility or process-targeted keyboard paths.

`SystemTerminalTextPaster` performs the following sequence:

1. Snapshot all available pasteboard item representations.
2. Write the final output to `NSPasteboard.general`.
3. Post a frontmost-session Command-V event using `CGEvent` and `.cghidEventTap`.
4. Wait briefly for the frontmost terminal to consume the paste.
5. Restore the previous pasteboard item representations.
6. Report success only after the paste operation and restoration sequence completes.

The output is pasted into the frontmost terminal session; VoiceFlow does not execute a shell command or add an Enter key automatically. The user remains responsible for reviewing and submitting the command.

## Compatibility with other applications

Normal editable applications continue to use the existing Accessibility-first path and then process-targeted keyboard events. Terminal-family applications are treated as valid text-output targets even though their shell prompt may not expose a native AX text-field role. The higher-level clipboard fallback remains reserved for a missing target application or a non-terminal target with no supported focused text input.

If Accessibility/Input Monitoring permission is unavailable for a captured target, VoiceFlow preserves the existing actionable permission error path. It does not silently claim success or copy output to the clipboard merely because the target is Terminal.

## Clipboard privacy

The previous clipboard is restored after the terminal paste attempt, including available non-string item representations. The final transcription is not logged. If the paste command fails, VoiceFlow attempts restoration before reporting the error. Clipboard restoration is best effort at the system boundary; users should avoid changing the clipboard during the short paste window.

This feature introduces no network request and does not alter local transcription, AI opt-in behavior, snippet expansion, audio retention, or normal text injection. Logs report only safe metadata such as target bundle identifier, output method, process identifier, and error category.

## Implementation

| Component | Responsibility |
|---|---|
| `TerminalTextPasting` | Defines the injectable terminal paste contract. |
| `SystemTerminalTextPaster` | Snapshots/restores the pasteboard, writes temporary output, and posts Command-V. |
| `PasteboardSnapshot` | Preserves available pasteboard item data for restoration. |
| `PasteCommandPosting` | Defines an injectable paste-command event contract. |
| `CGEventPasteCommandPoster` | Posts Command-V through the frontmost HID event tap. |
| `TextInjector` | Routes supported Terminal-family targets to the paste path and keeps ordinary injection behavior unchanged. |
| `TextInjectorTests` | Covers Terminal classification, Terminal paste routing, and previous clipboard restoration. |

## Acceptance criteria

| Area | Acceptance criterion |
|---|---|
| Terminal routing | Supported Terminal-family bundle identifiers select the paste-based path. |
| Reliable delivery | Terminal output is delivered through temporary clipboard content plus frontmost Command-V. |
| Clipboard restoration | The clipboard contents that existed before the operation are restored after the paste attempt. |
| Normal applications | TextEdit and other ordinary apps retain the existing Accessibility-first injection path. |
| Permission handling | Missing Accessibility/Input Monitoring permission reports an actionable error and does not claim successful output. |
| Shell safety | VoiceFlow pastes text but does not submit the shell command automatically. |
| No-target fallback | No target or a supported non-text target continues to use the regular Copied to Clipboard flow. |
| Completion state | Successful Terminal output shows the normal Done state; failed output does not show false success. |
| Privacy | Audio, transcripts, commands, clipboard contents, and secrets remain absent from logs, and no network request is introduced. |
| Compatibility | Existing model, transcription, AI, snippets, retention, overlay, menu-bar, Settings, and text-field workflows remain intact. |

## Verification evidence

The test-first sequence added a red regression test requiring a Terminal paste writer before implementation. The focused `TextInjectorTests` suite completed with **9 tests and zero failures**. The complete `voiceflowTests` suite completed with **184 tests and zero failures**.

The final clean build produces:

```text
build/VoiceFlow.app
```

## Manual verification

1. Open `build/VoiceFlow.app` and grant Microphone and Accessibility/Input Monitoring permissions.
2. Open Apple Terminal or iTerm2 and focus a shell prompt.
3. Copy a harmless clipboard value such as `clipboard before test` so restoration can be checked.
4. Hold Fn, speak a short non-sensitive sentence or command, and release Fn.
5. Confirm the output appears at the terminal prompt, the overlay shows Done, and the previous clipboard value is restored afterward.
6. Confirm VoiceFlow does not press Enter automatically.
7. Test TextEdit separately and confirm its normal injection path still works.
8. With no active text input, confirm the separate clipboard fallback displays Copied to Clipboard.

If Terminal still does not receive output, verify the exact app at `build/VoiceFlow.app` has Accessibility/Input Monitoring permission, remains frontmost from recording start through paste, and is one of the supported bundle identifiers.

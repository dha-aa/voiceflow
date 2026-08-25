# Change 027: Terminal-Compatible Text Injection

## Summary

VoiceFlow now supports text output to Terminal-family applications that do not reliably accept process-targeted `CGEvent` keyboard events. The existing Accessibility-first injection path remains unchanged for standard editable applications. When the captured target application is a supported terminal emulator, VoiceFlow uses frontmost-session keyboard events so the shell receives the generated text as ordinary keyboard input.

The output flow is:

> Capture target application at Fn hold → transcribe/process locally → determine output target → use Accessibility injection for normal editable controls or frontmost-session keyboard events for Terminal-family apps → show completion state

## Supported Terminal targets

The routing decision is based on the captured application bundle identifier. The current Terminal-family set is:

| Application | Bundle identifier |
|---|---|
| Apple Terminal | `com.apple.Terminal` |
| iTerm2 | `com.googlecode.iterm2` |
| Alacritty | `io.alacritty` |
| Ghostty | `com.mitchellh.ghostty` |
| Kitty | `net.kovidgoyal.kitty` |
| WezTerm | `org.wezfurlong.wezterm` |

The routing helper is centralized in `TextInjector.usesFrontmostKeyboardEvents(for:)`. Unknown applications continue to use the existing process-targeted keyboard path. The supported list can be extended when another terminal emulator’s event behavior is verified.

## Injection behavior

`TextInjector` continues to attempt the Accessibility API first for ordinary applications. If that path cannot update the focused value, it falls back to keyboard events. For a supported Terminal-family application, the keyboard event poster sends each Unicode chunk through `CGEvent.post(tap: .cghidEventTap)` rather than `postToPid(_:)`. This delivers text to the frontmost terminal session while preserving the existing chunking, Unicode handling, permission checks, and error mapping.

Terminal applications are treated as text-output targets by `hasTextInput(in:)` when Accessibility permission is available. This prevents the higher-level `InjectionCoordinator` from incorrectly choosing the clipboard fallback merely because a terminal prompt does not expose the same focused text-field Accessibility roles as a native text editor.

If Accessibility permission is denied, VoiceFlow does not silently copy terminal output to the clipboard. It follows the existing permission-denied error path and asks the user to grant the required macOS permission. If no target application exists, or a non-terminal target has no supported focused text input while Accessibility is available, the separate clipboard fallback from Change 026 remains active.

## Privacy and safety

The Terminal fix does not create a network request and does not change local transcription, AI opt-in behavior, snippet expansion, audio retention, or clipboard privacy. Logs report only metadata such as the target bundle identifier, process identifier, injection method, and success/error category. They do not record command text, transcription text, audio, clipboard contents, or secrets.

The frontmost-session event path requires the user’s normal macOS Accessibility/Input Monitoring authorization. VoiceFlow does not execute commands itself; it only types the final output into the captured terminal session. Users should verify the target shell prompt before releasing Fn.

## Implementation

| Component | Responsibility |
|---|---|
| `TextInjector.usesFrontmostKeyboardEvents(for:)` | Classifies supported terminal-emulator bundle identifiers. |
| `TextInputAvailabilityChecking` | Allows the coordinator to recognize terminal output as a supported text target without relying on an AX text-field role. |
| `CGEventKeyboardEventPoster` | Sends terminal text through the frontmost HID event tap and retains process-targeted events for other applications. |
| `InjectionCoordinator` | Preserves the permission error path, selects clipboard output only for a genuinely missing target or focused text input, and keeps normal completion states. |
| `TextInjectorTests` | Covers the terminal-family classification and existing injection/error contracts. |
| `docs/testing.md` | Adds manual Terminal verification requirements. |

## Acceptance criteria

| Area | Acceptance criterion |
|---|---|
| Terminal routing | Apple Terminal and supported terminal-emulator bundle identifiers select frontmost-session keyboard events. |
| Normal applications | TextEdit and other non-terminal applications retain the existing injection path. |
| Accessibility | Missing Accessibility permission produces an actionable error instead of silently claiming clipboard success. |
| Clipboard fallback | Clipboard output remains available for no target or a non-terminal target with no focused text input. |
| Unicode | Existing Unicode and chunked keyboard-event behavior remains intact. |
| Shell input | With Terminal focused and permissions granted, released Fn output appears at the shell prompt without requiring manual copy/paste. |
| Completion | Successful terminal output shows the normal Done state; failures do not show false success. |
| Privacy | No audio, transcript, command, inserted text, or clipboard contents are logged, and no network request is introduced. |
| Compatibility | WhisperKit, FluidAudio, AI routing, snippets, retention, overlay, menu bar, settings, and normal text-field injection remain unchanged. |

## Verification evidence

The test-first sequence added a failing regression test for Terminal-family routing before the implementation. The focused `TextInjectorTests` suite then completed with **7 tests and zero failures**. The complete `voiceflowTests` suite completed with **182 tests and zero failures**.

The final build completed successfully and produced:

```text
build/VoiceFlow.app
```

## Manual verification

1. Open the built VoiceFlow app and grant Microphone and Accessibility/Input Monitoring permissions.
2. Open Apple Terminal or iTerm2 and focus a shell prompt.
3. Hold Fn, speak a short non-sensitive sentence or command, and release Fn.
4. Confirm the overlay shows Listening and Processing, then the result appears at the shell prompt and the overlay shows Done.
5. Confirm a normal TextEdit field still receives text through the existing path.
6. Confirm that with no target text field, the result is copied to the clipboard and the overlay says Copied to Clipboard.

If Terminal still does not receive output, verify that the exact build at `build/VoiceFlow.app` has Accessibility/Input Monitoring permission and that the terminal window remained frontmost from recording start through output delivery.

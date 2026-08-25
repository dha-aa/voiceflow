# Change 029: Output Caret Normalization

## Summary

VoiceFlow now normalizes the insertion position after output so the caret is at the end of the resulting text or terminal input line. This addresses cases where output appeared to leave the cursor at the beginning or leave the terminal line in an unexpected selection state.

## Normal application injection

After replacing the focused Accessibility element’s selected range, `TextInjector` sets `kAXSelectedTextRangeAttribute` to a zero-length range at the end of the resulting value. The helper `TextInjector.endCaretLocation(existingText:selectedRange:replacement:)` calculates the resulting UTF-16 length safely, including replacement of a selected range and Unicode text.

The resulting behavior is:

> Existing text + selected-range replacement → updated value → zero-length caret at the end of the updated value

This behavior applies to the existing Accessibility injection path and does not alter text content or selection replacement semantics.

## Terminal injection

Terminal-family applications continue to use the reliable paste path from Change 028. After the temporary clipboard value is pasted with frontmost Command-V, VoiceFlow posts a Control-E event through the same frontmost HID event tap. Control-E is the standard shell line-editing command for moving the cursor to the end of the current input line. VoiceFlow then waits briefly before restoring the previous clipboard contents.

VoiceFlow does not post Enter and does not execute the shell command. The user can review or edit the pasted text at the end of the prompt before submitting it.

## Privacy and compatibility

The change does not create a network request and does not alter local transcription, AI routing, Snippets, audio retention, clipboard fallback, model management, or completion behavior. Logs continue to report only output method and lifecycle metadata; they do not contain dictated text, command text, audio, or clipboard contents.

## Implementation

| Component | Responsibility |
|---|---|
| `TextInjector.endCaretLocation` | Computes the end position of the resulting Accessibility value. |
| `injectUsingAccessibilityAPI` | Sets the post-replacement caret to the resulting text end. |
| `PasteCommandPosting.postEndOfLineCommand` | Provides an injectable terminal line-end command. |
| `CGEventPasteCommandPoster` | Posts Control-E through the frontmost HID event tap after Terminal paste. |
| `SystemTerminalTextPaster` | Coordinates paste, end-of-line normalization, delay, and clipboard restoration. |
| `TextInjectorTests` | Covers caret calculation, Terminal end-of-line sequencing, paste routing, and clipboard restoration. |

## Acceptance criteria

| Area | Acceptance criterion |
|---|---|
| Text-field caret | After normal Accessibility replacement, the caret is at the end of the resulting value. |
| Terminal caret | After Terminal paste, the shell input caret is moved to the end of the current line. |
| Selection behavior | Terminal output is not left at the beginning of the line due to a stale selection or cursor position. |
| Shell safety | No Enter key is posted and no command is executed automatically. |
| Clipboard | The user’s previous clipboard contents are restored after the paste and caret-normalization sequence. |
| Compatibility | Normal TextEdit injection, no-target clipboard fallback, AI processing, Snippets, audio retention, model workflows, and overlay behavior remain intact. |
| Privacy | No output text, command text, clipboard contents, or audio is logged, and no network request is introduced. |

## Verification evidence

The test-first sequence added red regressions for end-of-text caret calculation and Terminal end-of-line sequencing before implementation. The focused `TextInjectorTests` suite completed with **11 tests and zero failures**. The complete `voiceflowTests` suite completed with **186 tests and zero failures**.

The clean build produces:

```text
build/VoiceFlow.app
```

## Manual verification

1. Open the built app and grant Microphone and Accessibility/Input Monitoring permissions.
2. Focus an editable TextEdit field, place the insertion point or select text, dictate, and confirm the resulting caret is at the end of the updated text.
3. Focus a Terminal shell prompt and copy a harmless clipboard value for the restoration check.
4. Dictate a short harmless command, release Fn, and confirm the text appears at the end of the shell input line without the entire line remaining selected.
5. Confirm the previous clipboard value is restored and Enter is not sent automatically.

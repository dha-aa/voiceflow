# Specification Change 020 — AI Selection, Prompt, Onboarding, and Window Stability

## Summary

This change fixes five user-reported regressions without changing VoiceFlow’s existing **Fn → local speech-to-text → text processing → optional AI → text injection** workflow. It makes selected-text context stable across the asynchronous recording/transcription boundary, improves provider-neutral prompt contracts for natural voice instructions and grammar correction, restores durable onboarding completion state, and prevents onboarding windows from being recreated or reopened after setup is complete.

## Selection-aware AI behavior

When the Fn key goes down, `RecordingCoordinator` captures the frontmost `NSRunningApplication` and, when configured, reads the current focused selection through `FocusedTextSelectionReading`. The captured selection is kept with the recording context until the recording-completion callback is delivered. This avoids relying exclusively on the target application’s live focus state after local transcription and AI processing have completed.

Production wiring passes the existing `TextInjector` as the selection reader. The existing two-argument `onRecordingComplete` callback remains available for compatibility; the production composition root uses `onRecordingCompleteWithContext`, which carries the audio URL, target application, and captured selection into `TranscriptionCoordinator`.

`TranscriptionCoordinator.transcribe(audioURL:targetApp:selectedText:)` forwards the selection to `ClaudeCommandProcessor`. For an explicit configured AI prefix command, the processor prefers a non-empty captured selection and otherwise falls back to its existing live selection reader. The request contains the user’s prefix-stripped instruction and the selected text. `AIProcessingRequest` continues to suppress broader screen context whenever selected text is present. The Claude client formats the request as selected material plus an instruction, and the returned result follows the existing injection path so it replaces the selected range.

Selection is never sent for ordinary dictation or grammar correction. AI prefix detection continues to occur before grammar correction, so enabling Grammar Fix cannot rewrite or interfere with an explicit AI command. Empty, whitespace-only, unavailable, or invalid selections are treated as absent and do not cause a request failure.

## Accessibility selected-text fallback

`TextInjector.selectedText(in:)` first attempts `kAXSelectedTextAttribute`. For controls that do not expose that attribute but do expose `kAXValueAttribute` and `kAXSelectedTextRangeAttribute`, it now derives the selection from the focused value and range. Extraction uses `NSString`/UTF-16 offsets, matching the existing accessibility injection logic. Zero-length, out-of-bounds, and whitespace-only ranges return no selection. No selected text is written to logs.

## AI prompt contracts

`AIPromptBuilder.command` is provider-neutral and compact enough for routine voice use. It instructs the provider to interpret natural, incomplete, or imperfect speech, infer the intended transformation, use selected text as the material when supplied, preserve essential meaning unless change is requested, and return only paste-ready final content. It prohibits explanations, preambles, quotes, Markdown, and unrequested content while requiring valid formatting for code, commands, lists, and line breaks.

`AIPromptBuilder.grammarFix` is a correction-only contract. It requires correction of grammar, spelling, capitalization, punctuation, sentence structure, and obvious speech-to-text errors. It preserves meaning, wording, tone, and information and limits changes to necessary corrections. It explicitly prohibits answers, explanations, rewriting, additions, removals, quotes, and Markdown; the provider must return corrected text only.

These prompt strings remain independent of Claude-specific API details so a future provider can reuse the same `AIProcessingRequest` and prompt-builder contracts.

## Onboarding lifecycle

`OnboardingModel` restores `.complete` when `hasCompletedOnboarding` is already true. Both `skipSetup()` and `finish()` persist the completion key and set the in-memory step to `.complete` before invoking the completion callback. This keeps a relaunched model consistent with the persisted state.

`OnboardingWindowController.shouldShowOnLaunch(userDefaults:)` is the single completion policy used by both `showIfNeeded` and `show`. A completed setup therefore cannot be opened by the launch flow or by a stale explicit show request. The controller assigns itself as the window delegate, clears the closed window reference during `finish()`, and guards against re-entrant close handling.

Closing the onboarding window through its explicit close control is treated as **Skip setup for now**. The completion key is persisted so onboarding does not unexpectedly reappear on every launch. Skipped or denied permissions remain represented by the completion summary and can be granted later through Settings. The app still presents onboarding at launch only through the defined first-launch call in `AppDelegate`; `VoiceFlowApp` declares no `WindowGroup` or default SwiftUI application window.

The Settings window remains explicitly user-triggered by the Settings action in `MenuBarPopoverView`. This change introduces no automatic Settings presentation and does not alter Settings/model-management behavior.

## Privacy and compatibility requirements

Speech recognition remains local through the existing WhisperKit or FluidAudio/Parakeet engines. Only an explicit configured AI-prefix command may send text to the configured AI provider. Selection content is sent only for that AI request, and selected text continues to suppress broader screen context. Audio, transcripts, selection contents, prompts, and provider responses are not logged. Existing provider/model selection, keychain storage, model preloading, overlay state transitions, injection, completion sounds, and menu-bar behavior remain unchanged.

## Test-first verification

The unchanged baseline suite completed before implementation with **148 tests and zero failures**. New regression tests were then added for Fn-time selection capture, AI selection forwarding, the AX value/range extraction contract, natural-speech command prompts, correction-only grammar prompts, durable onboarding completion, and launch presentation policy. Against the previous implementation, the new tests failed through missing selection/presentation interfaces and unmet behavior assertions.

After implementation, the focused regression set completed with **6 tests and zero failures**. The complete `voiceflowTests` suite completed with **154 tests and zero failures**.

## Acceptance criteria

| Area | Acceptance criterion |
|---|---|
| Selection capture | Selection is snapshotted with the target application at Fn-down and is available when transcription finishes. |
| AI request | An explicit AI command receives the prefix-stripped instruction and selected text, and the result follows the existing replacement injection path. |
| Selection privacy | A non-empty selection suppresses screen context; ordinary dictation and Grammar Fix do not send selection content. |
| AX compatibility | Controls exposing only AX value and selected range still produce a valid UTF-16-safe selection. |
| Prompt intent | Natural, incomplete, and imperfect voice instructions are interpreted as transformation requests and return direct paste-ready output only. |
| Grammar Fix | Grammar, spelling, punctuation, sentence structure, and obvious STT errors are corrected with minimal wording/meaning changes and no explanation. |
| Onboarding | Completed onboarding restores complete state, persists through relaunch, and is not reopened by the launch check or stale controller state. |
| Window behavior | No default SwiftUI window or automatic Settings window is introduced; onboarding opens only through the defined first-launch flow or explicit onboarding action. |
| Validation | All 154 XCTest cases pass after implementation. |

## Scope and limits

This change does not add a new AI provider, screen-capture implementation, remote speech recognition, or a new window/navigation surface. Real-world accessibility behavior remains dependent on the target application exposing a focused accessibility element and on the user granting macOS Accessibility permission. Manual verification should cover a native text field and a web-backed/editor control with selected text, plus first launch, Skip setup, completion, and relaunch behavior.

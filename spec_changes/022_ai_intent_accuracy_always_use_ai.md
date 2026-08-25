# Specification Change 022 — Accuracy-First AI Intent Handling and Always Use AI

## Summary

This change prioritizes accurate interpretation of spoken AI requests over prompt-token minimization. Claude command processing now receives a detailed provider-neutral system prompt that requires intent analysis, requested-output classification, format selection, context resolution, preservation of user constraints, and direct paste-ready output. An opt-in **Always use AI (no prefix)** preference allows users to send every non-empty dictated utterance to the selected AI provider without speaking the configured command prefix.

## Accuracy-first command prompt

`AIPromptBuilder.command` now instructs the model to interpret natural, incomplete, imperfect, and speech-to-text input without requiring polished grammar. The model must determine what the user wants to accomplish, the intended audience and context, the requested operation, the expected output type, and the format that best satisfies the request.

The prompt distinguishes writing, rewriting, transformation, shortening, expansion, correction, translation, explanation, summarization, extraction, organization, listing, formatting, and conversion. It explicitly requires structured output when the request implies structure. For example, a request to “take a note of three things” should produce a direct numbered or bulleted note rather than a conversational acknowledgement.

The model must use selected text as transformation material and the spoken request as the instruction. It may resolve references using selected text or approved screen context, but must not invent missing facts. It must preserve names, numbers, links, code semantics, constraints, and requested detail. It must not ask a follow-up question when information is incomplete; it should produce the most useful supported output from the available input.

The response contract remains direct-injection oriented: return only the final output requested by the user, with no analysis, reasoning, intent labels, confirmations, filler, preamble, explanation, quotation marks, or unrequested Markdown. Markdown is allowed when requested or when needed to produce the requested structure or preserve the source format.

## Always Use AI setting

`AISettings.alwaysUseAIKey` stores the opt-in preference, and `AISettings.alwaysUseAI(in:)` reads it with a default of `false`. `AISettingsView` exposes the setting as **Always use AI (no prefix)** in the Claude section. Its explanation states that every non-empty dictated utterance is sent to Claude without the configured prefix and that the setting is off by default.

When Always Use AI is enabled, the Claude processor treats any non-empty transcript as a command prompt. The command prompt is the complete trimmed transcript; no prefix is removed. The setting is self-sufficient and does not require the separate **Enable Claude commands** toggle. The selected provider must still be Claude and a configured Keychain API key is still required before a request is sent.

When Always Use AI is disabled, explicit prefix commands retain the existing behavior and normal unprefixed dictation remains local unless Grammar Fix is enabled. When Grammar Fix and Always Use AI are both enabled, Always Use AI selects command mode for non-empty speech, so Grammar Fix does not rewrite the user’s AI request first. An explicit configured prefix always remains recognized and is stripped before the request is sent.

## Privacy and pipeline compatibility

The change does not alter local speech recognition, target-application capture, selected-text forwarding, selection-over-screen-context privacy, model management, injection, or overlay state handling. Always Use AI is deliberately opt-in because it sends ordinary dictated text to the configured provider; with the preference off, ordinary dictation remains local under the existing rules. Audio is never sent to the AI provider, and prompts, responses, API keys, and dictated content are not written to logs.

## Testing and acceptance criteria

| Area | Acceptance criterion |
|---|---|
| Intent understanding | The command prompt explicitly directs the provider to infer intent from natural, incomplete, imperfect, and speech-to-text input. |
| Output format | The provider determines the requested output type and emits the requested structure directly, including numbered notes and lists. |
| Context | Selected text is treated as transformation material; available context resolves references without inventing facts. |
| Response contract | The provider returns only final paste-ready output without analysis, explanation, acknowledgement, or unrequested formatting. |
| Always Use AI default | A fresh defaults domain reports `false` for Always Use AI. |
| Always Use AI routing | When enabled, any non-empty unprefixed transcript is sent in command mode without requiring the command-prefix toggle. |
| Precedence | Always Use AI command mode and explicit prefix commands take precedence over Grammar Fix. |
| Opt-in privacy | With Always Use AI disabled, unprefixed ordinary dictation does not call Claude unless Grammar Fix is separately enabled. |
| Validation | The unchanged baseline completed with **160 tests and zero failures**. New focused AI/settings coverage completed with **35 tests and zero failures**. The final full suite completed with **164 tests and zero failures**. |

## Implementation note

A pre-existing coordinator test was made deterministic by injecting an isolated AI settings domain. This prevents persisted user preferences from the developer’s local installation from changing a test that is intended to exercise only local transcription and injection-state transitions.

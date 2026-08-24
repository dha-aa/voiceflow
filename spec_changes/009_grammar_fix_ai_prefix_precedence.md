# Specification Change 009 — Grammar Fix and AI-Prefix Precedence

## Summary

VoiceFlow now treats an explicit configured AI prefix as higher priority than Grammar Fix. This prevents the correction engine from changing an AI request before the provider receives it.

## Routing contract

Local WhisperKit transcription and the existing `TextProcessor` run first. `ClaudeCommandProcessor.processTranscribedText(_:)` then evaluates the configured AI prefix before considering Grammar Fix.

| AI prefix detected | Grammar Fix | Result |
|---|---|---|
| Yes | On | Remove the prefix and send only the remainder to Claude as an AI request. Do not run Grammar Fix first. |
| Yes | Off | Remove the prefix and send only the remainder to Claude as an AI request. |
| No | On | Send the complete ordinary transcript to Claude with the correction-only system prompt. |
| No | Off | Keep the processed transcript local and inject it unchanged. |

A matching prefix is case-insensitive and follows the existing leading-boundary rules. Grammar Fix never modifies a matching AI command before prefix removal.

## Grammar correction contract

The AI Settings pane contains **Fix Grammar & Punctuation**, persisted by `grammarFixEnabled` and disabled by default. When enabled for ordinary no-prefix speech, Claude receives the complete processed transcript and a system instruction to:

- Correct grammar, spelling, capitalization, and punctuation only.
- Preserve wording, meaning, tone, and information as much as possible.
- Return only corrected text ready for direct injection.
- Avoid explanations, rewriting, paraphrasing, summaries, new information, Markdown, and quotation wrappers.

The API response is trimmed and rejected when empty. API keys, input text, system prompts, responses, audio, and injected text remain excluded from logs.

## Implementation

- `AISettings.grammarFixEnabledKey` stores the toggle preference.
- `ClaudeSettings.grammarCorrectionSystemPrompt` is the correction-only system prompt.
- `ClaudeAPIClient.complete(..., systemPrompt:)` supports both ordinary Claude requests and correction requests.
- `ClaudeCommandProcessor.processTranscribedText(_:)` owns the precedence rule.
- `TranscriptionCoordinator` calls the unified processor before the injection transition.

## Verification

Deterministic tests cover all four combinations, confirm that AI commands receive only the prefix remainder, confirm that Grammar Fix receives the complete ordinary transcript with the system prompt, and confirm that ordinary local dictation bypasses Claude when both routes are disabled. No real Anthropic API key or live request is required for automated verification.

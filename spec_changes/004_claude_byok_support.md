# Specification Change 004 — Claude BYOK Support

## Summary

VoiceFlow now supports an optional Claude command path using a user-provided Anthropic API key. The existing local microphone capture, WhisperKit transcription, TextProcessor cleanup, target-app capture, Accessibility-first injection, completion state, and completion sound behavior remain in place.

## User flow

When Claude commands are disabled, all dictated text follows the existing local transcription-to-injection path. When enabled, a transcript is routed to Claude only when its first word is `Claude`, case-insensitively, with optional punctuation. VoiceFlow removes that command word and sends only the remaining prompt:

```text
Voice input
  → local microphone capture
  → local WhisperKit transcription
  → TextProcessor cleanup
  → detect leading “Claude” command
  → HTTPS Anthropic Messages API request
  → Claude text response
  → existing text injection path
```

For example, `Claude, rewrite this politely` sends only `rewrite this politely` to Claude. A normal transcript without that prefix never calls the network.

## Settings and credential storage

General Settings now provides:

- `Enable Claude commands`, disabled by default.
- An editable Claude model ID, initialized to `claude-sonnet-5`.
- A secure Anthropic API-key entry field.
- Save and remove controls.
- Keychain status without displaying the stored secret.

The API key is stored in the macOS Keychain using the application bundle identifier as the service. It is not stored in UserDefaults, source files, model directories, logs, or command-line arguments. Keychain read, save, and removal failures are surfaced as configuration failures.

## API implementation

`voiceflow/Core/LLM/ClaudeClient.swift` contains:

- `ClaudeAPIClient` for dependency-injected request testing.
- `KeychainClaudeAPIKeyStore` for secure local credential storage.
- `ClaudeCommandProcessor` for configuration checks, prefix parsing, request routing, and response validation.
- `LiveClaudeAPIClient` for direct HTTPS requests to `https://api.anthropic.com/v1/messages`.
- `ClaudeCommandError` for missing configuration, Keychain failure, request failure, and empty response states.

Requests use the Anthropic direct API headers:

```text
x-api-key: <user key>
anthropic-version: 2023-06-01
content-type: application/json
```

The request contains a single user message and a bounded `max_tokens` value. The response parser accepts text content blocks only and rejects empty responses.

## Pipeline integration

`TranscriptionCoordinator` receives a `ClaudeCommandProcessor`. After the local `TextProcessor` runs, the coordinator optionally awaits Claude processing. Only the final local or Claude-produced text transitions the state to `.injecting` and reaches `InjectionCoordinator`.

Claude configuration failures map to `.claudeNotConfigured`. Request, decoding, and empty-response failures map to `.claudeRequestFailed`. The state manager then follows the existing recoverable error behavior.

## Privacy boundary

Audio capture, temporary WAV files, WhisperKit model files, and default transcription remain local. The user explicitly opts into sending text to Anthropic by enabling Claude commands and speaking the `Claude` command prefix. VoiceFlow does not send audio to Anthropic.

Logs remain metadata-only. They may contain the provider/model identifier, prompt and response character counts, duration, and error category. They must not contain API keys, prompts, responses, audio, raw local transcription, or injected text.

## Tests and validation

`voiceflowTests/LLM/ClaudeClientTests.swift` covers:

- Case-insensitive `Claude` prefix parsing.
- Punctuation removal around the command prefix.
- Bypassing Claude for normal dictation.
- Forwarding only the prompt remainder.
- Model and API-key forwarding through injected test doubles.
- Missing-key rejection.
- Coordinator routing and injection of a mocked Claude response.

Focused Claude/settings/transcription tests passed with zero failures. The full VoiceFlow test suite passed:

```text
Executed 110 tests, with 0 failures
** TEST SUCCEEDED **
```

No real Anthropic request or real API key is used by the automated tests.

## Documentation updates

The implementation is documented in:

- `README.md` — Claude setup and privacy boundary.
- `docs/testing.md` — manual Claude setup and disposable TextEdit verification.
- `specs/spec_03_transcription.md` — routing and lifecycle contract.
- `specs/spec_04_text_injection.md` — final-text handoff semantics.
- `specs/spec_06_settings_and_model_management.md` — General Settings controls.
- `specs/spec_07_production_readiness.md` — optional network boundary and security requirements.

## References

- [Anthropic API authentication](https://platform.claude.com/docs/en/manage-claude/authentication)
- [Anthropic Messages API](https://platform.claude.com/docs/en/api/messages)
- [Anthropic model IDs and versioning](https://platform.claude.com/docs/en/about-claude/models/model-ids-and-versions)

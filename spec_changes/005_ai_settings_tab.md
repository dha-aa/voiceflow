# Specification Change 005 — AI Settings Tab and Claude Model Discovery

## Summary

VoiceFlow now has a dedicated **AI** tab in Settings. The tab separates AI provider configuration from General preferences and introduces a provider-neutral settings structure while keeping Claude as the only implemented provider.

The existing voice flow remains unchanged at its boundaries:

```text
Voice input → local WhisperKit transcription → explicit AI command routing
→ provider response → existing text injection
```

Ordinary dictation continues to bypass all AI requests.

## AI provider architecture

`voiceflow/Core/LLM/AISettings.swift` defines `AIProvider`, `AIModel`, provider selection, per-provider model persistence, and the provider-neutral model/key-store contracts.

The current provider registry contains:

| Provider | Settings visibility | Model discovery | Voice request path |
|---|---|---|---|
| Claude | Implemented and selectable | Authenticated Anthropic Models API | Implemented |
| ChatGPT | Visible as coming soon | Not implemented | Not implemented |

ChatGPT is represented in the data model so a later implementation can add its own Keychain account, model catalog client, request client, and command routing without replacing the Settings navigation or transcription coordinator.

## Settings behavior

`SettingsView.Destination` now contains **General**, **AI**, **Models**, and **About**. `AISettingsView` provides:

- Default AI provider selection, defaulting to Claude.
- Claude command enablement, disabled by default.
- Claude API-key entry and save/remove controls.
- Claude model selection using a per-provider UserDefaults key.
- Manual model-ID entry when no remote model list has been fetched.
- A user-triggered **Fetch available models** action.
- A clearly labeled ChatGPT coming-soon section.

The old Claude controls were removed from `GeneralSettingsView` so there is one authoritative configuration surface.

## Persistence and migration

The selected provider is stored in `aiSelectedProvider`. Provider model IDs are stored with keys such as `aiModel.claude`. The previous `claudeModel` preference is read as a migration fallback, so an existing Claude configuration continues to work before the user opens the AI tab.

Claude’s API key remains Keychain-only. The provider-specific Keychain account is `anthropic-api-key`; no secret is stored in UserDefaults or displayed after saving. A future ChatGPT implementation is reserved for the `openai-api-key` account and must follow the same rule.

## Claude model discovery

`voiceflow/Core/LLM/AIModelCatalog.swift` implements `LiveClaudeModelCatalogClient`. It calls the authenticated Anthropic `GET https://api.anthropic.com/v1/models` endpoint with the user’s saved key and the required Anthropic version header. The response’s model IDs and display names are converted into sorted `AIModel` values for the picker.

Model refresh is intentionally user-triggered. A refresh failure does not erase the manually selected model, and the UI reports that the key or network should be checked. No API key, prompt, response, audio, or transcript is logged.

## Routing contract

`ClaudeCommandProcessor` now checks both the Claude command flag and the selected provider. Only when Claude is enabled, Claude is selected, and the local processed transcript begins with the leading `Claude` command does VoiceFlow call the Claude request client. The command word and optional punctuation are removed; only the remainder is sent. The returned text is passed to the existing injection coordinator.

If a future provider is selected without an implemented request path, the current Claude processor bypasses rather than making an unintended request. ChatGPT must not be presented as operational until its API client, model catalog, key handling, routing, errors, and tests exist.

## Tests

The change adds deterministic coverage for:

- Four-pane Settings navigation.
- Claude-default provider selection.
- Per-provider model persistence.
- Legacy Claude model migration fallback.
- AI Settings view construction.
- Anthropic model-list decoding, display-name fallback, and stable sorting.
- Existing Claude prefix parsing, bypass, key handling, response routing, and coordinator injection.

The model-list tests use fixture JSON and do not contact Anthropic or require a real API key.

## Manual verification

A manual check should open **Settings → AI**, confirm the default Claude provider, save a disposable Anthropic key, fetch the available model list, select a model, close and reopen Settings, and confirm the selection persists. A disposable TextEdit request beginning with `Claude` should inject the returned response. A normal dictation without the prefix must remain local. ChatGPT should be visibly marked as coming soon and must make no request in this release.

## References

- [Anthropic Models API — List Models](https://platform.claude.com/docs/en/api/models/list)
- [Anthropic API authentication](https://platform.claude.com/docs/en/manage-claude/authentication)
- [OpenAI Models API reference](https://developers.openai.com/api/reference/resources/models/methods/list/)

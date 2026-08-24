# Specification Change 006 — Custom AI Prefix and API-Key UX

## Summary

VoiceFlow’s Claude-first AI configuration is now customizable and exposes a clearer credential lifecycle. The AI provider, model, API key, and command prefix are configured together in **Settings → AI**.

The runtime flow is:

```text
Voice input → local transcription → configured-prefix detection
→ prefix removal → selected Claude model → response → existing injection
```

Normal dictation remains local and does not contact Claude.

## Custom command prefix

The AI command prefix is persisted in `aiCommandPrefix` and defaults to `Claude`. The user may replace it with any non-empty word or phrase, including `Ask Claude`, `AI`, `@claude`, or `Jarvis`.

Matching is case-insensitive and must occur at the beginning of the processed transcript. The parser requires a boundary after the configured prefix: whitespace or optional punctuation may follow it, but a prefix embedded in a larger word does not match. The prefix and surrounding command punctuation are removed before the request is sent.

Examples:

| Configured prefix | Transcript | Prompt sent to Claude |
|---|---|---|
| `Claude` | `Claude explain this code` | `explain this code` |
| `Ask Claude` | `ask claude, summarize this` | `summarize this` |
| `AI` | `AI: translate this` | `translate this` |
| `Jarvis` | `Jarvis rewrite this politely` | `rewrite this politely` |

An empty or whitespace-only stored prefix resolves to the default `Claude` prefix, preventing accidental all-text routing.

## Provider and model behavior

Claude remains the only implemented provider. Routing requires Claude commands to be enabled, Claude to be selected as the provider, and the configured prefix to match at the start of the local transcript. The selected Claude model is read from the persisted per-provider model key and may be entered manually or fetched from Anthropic’s authenticated Models API.

ChatGPT remains a future provider represented in the settings architecture. It has no active API-key storage, model discovery, request, or injection path in this change.

## API-key experience

The AI tab now separates editing from the saved credential state:

- When no key is configured, the SecureField and `Save API key` control are shown.
- After a successful save, the input is cleared, the secret remains only in the macOS Keychain, and the UI shows a fixed masked value such as `••••••••••••••••`.
- The status is shown as `Configured` without revealing the key or its length.
- `Change API Key` returns to the SecureField so the user can replace the stored credential.
- `Remove API Key` deletes the Keychain item and returns the UI to the unconfigured state.
- Keychain read, save, and remove failures are shown as actionable status messages.

The prefix, selected provider, command enablement, and model choice are stored in UserDefaults. The API key is never stored in UserDefaults, source control, logs, model files, or command-line arguments.

## Tests

Deterministic tests cover:

- Custom word and multi-word prefix parsing.
- Case-insensitive matching.
- Optional punctuation removal.
- Rejection of prefixes embedded in another word.
- Default and persisted custom prefix values.
- Claude processor forwarding only the post-prefix prompt.
- Existing normal-dictation bypass and coordinator response injection.
- Existing AI Settings construction and provider/model persistence.

No real Anthropic key or network request is used by the automated tests.

## Manual verification

Open **Settings → AI**, enter a disposable Anthropic API key, and save it. Confirm the UI shows a masked value and `Configured`, then use **Change API Key** and **Remove API Key**. Set `Jarvis` as the prefix, close and reopen Settings, and verify it persists. With Claude commands enabled, say `Jarvis, explain this code` and confirm only the Claude response is injected. Dictate a sentence without `Jarvis` and confirm it remains on the local path.

## References

- [Anthropic API authentication](https://platform.claude.com/docs/en/manage-claude/authentication)
- [Anthropic List Models API](https://platform.claude.com/docs/en/api/models/list)

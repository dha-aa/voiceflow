# Specification Change 010 — Compact Claude System Prompts

## Summary

VoiceFlow now uses short, mode-specific Claude system prompts instead of one long general-purpose instruction. This reduces repeated input tokens while preserving direct-injection safety and the existing AI-command and Grammar Fix contracts.

## Prompts

### AI command mode

```text
Return only the final content requested, ready to paste. Preserve the user’s intent. No explanations, filler, or unrequested information. Keep requested code, commands, lists, and line breaks valid.
```

### Grammar Fix mode

```text
Correct grammar, spelling, capitalization, punctuation, and obvious transcription errors only. Preserve meaning, wording, tone, and information. Return only the corrected text; no explanations, rewriting, Markdown, quotes, or added content.
```

The command prompt preserves the important behaviors from the supplied longer prompt: final-output-only responses, direct injection readiness, intent preservation, no conversational filler, and valid formatting for code, commands, lists, and multi-line content. Screen-context instructions were not included because screen-context AI is not implemented in the current VoiceFlow version.

## Request behavior

AI commands use the command-mode prompt. Grammar Fix uses the correction-mode prompt. Ordinary local dictation sends no system prompt and makes no Claude request. AI-prefix detection still runs before Grammar Fix, so a command is never grammar-corrected first.

The API key, user input, system prompt, response, audio, transcript, and injected text remain excluded from logs. Automated tests use a fake Claude client and do not make a live request.

## Verification

Claude tests verify that AI requests receive the command prompt, Grammar Fix requests receive the correction prompt, the correct input is forwarded for each mode, and the existing four precedence cases remain valid. The prompt text is intentionally concise and reusable rather than embedding lengthy examples or workflow descriptions in every request.

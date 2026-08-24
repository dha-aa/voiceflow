# Specification Change 012 — Selection-Aware AI Context

## Summary

VoiceFlow now supports using the user’s currently selected text as narrow context for an explicit AI-prefix command. The feature reuses the existing Accessibility focused-element path and final injection path; it does not capture the whole screen.

## Request behavior

After local transcription and AI-prefix detection, the processor preserves the instruction after the configured prefix. When the preserved target application exposes non-empty selected text through `FocusedTextSelectionReading`, the provider-neutral `AIProcessingRequest` contains:

- `text`: the spoken instruction after prefix removal.
- `mode`: `.command`.
- `model`: the selected provider-specific model.
- `selectedText`: only the selected text.
- `screenContext`: `nil`.

The Claude adapter encodes this as selected text plus instruction and returns only the provider result. The existing `TextInjector` then writes the result to the focused element and replaces the selected range, moving the caret after the replacement.

## Privacy boundary

Selection is the narrowest available context. If non-empty selected text is found, VoiceFlow does not call the broader screen-context provider, does not capture a screenshot, and does not send unrelated application content. Selection content is not logged. The current app has no screen-capture implementation; the existing screen-context slot remains inactive by default.

If no selection exists, or the selected-text reader cannot provide one, the command falls back to the ordinary instruction-only request plus any explicitly supplied future context. A selection-reader failure is treated as unavailable context so it does not prevent the normal AI command path; later Accessibility injection still reports its own permission or target failure normally.

## Scope and limitations

This feature applies to explicit AI-prefix command mode. It does not change Grammar Fix precedence or make normal dictation remote. Claude remains the only active provider. ChatGPT/OpenAI requests, multimodal screenshot handling, and automatic active-application interpretation remain future work.

## Verification

Automated tests use a fake selected-text reader and provider client to verify instruction separation, selected-text propagation, screen-context suppression, no-selection fallback, compact selection prompt instructions, model propagation, and no network or secret access. Manual verification should use a permitted text editor: select a paragraph, say `Claude make this shorter`, confirm only the selected range is replaced, then repeat with no selection and confirm the ordinary command path remains functional.

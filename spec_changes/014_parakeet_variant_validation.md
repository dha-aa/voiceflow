# Specification Change 014 — Parakeet Variant Validation and Cache Correction

## Summary

This corrective change fixes the Parakeet model lifecycle introduced by Specification Change 013. The original implementation pointed FluidAudio at a `*-coreml` folder name, while FluidAudio v0.15.6’s `Repo.folderName` stores the converted repository under the cache name without the `-coreml` suffix. The local cache observed during investigation was therefore `parakeet-tdt-0.6b-v3` and contained only partial download artifacts, while VoiceFlow was checking a different path. The generic invalid-model message also did not explain whether the user had selected an incomplete bundle or the raw NVIDIA repository.

Official repository inspection confirmed that `nvidia/parakeet-tdt-0.6b-v3` and `nvidia/parakeet-tdt-0.6b-v2` are upstream NeMo/Transformers repositories containing `.nemo`, `model.safetensors`, GGUF, tokenizer, and configuration artifacts. They are not directly loadable by FluidAudio. VoiceFlow now supports the corresponding Apple-platform conversions: `FluidInference/parakeet-tdt-0.6b-v3-coreml` and `FluidInference/parakeet-tdt-0.6b-v2-coreml`.

## Implemented changes

- Added `ParakeetModelVariant` with persisted `.v3` and `.v2` choices.
- Added explicit model metadata for display name, language coverage, FluidInference source repository, NVIDIA upstream lineage, FluidAudio version, precision, and canonical cache directory.
- Corrected the cache paths to `models/fluidaudio/parakeet-tdt-0.6b-v3` and `models/fluidaudio/parakeet-tdt-0.6b-v2`, matching FluidAudio’s repository-folder transformation.
- Updated `AsrModels.download`, `AsrModels.modelsExist`, and `AsrModels.load` calls to use the same variant and exact directory.
- Added exact structural validation for the v3 int8 set `{Preprocessor.mlmodelc, Encoder.mlmodelc, Decoder.mlmodelc, JointDecisionv3.mlmodelc, parakeet_vocab.json}` and v2 set `{Preprocessor.mlmodelc, Encoder.mlmodelc, Decoder.mlmodelc, JointDecision.mlmodelc, parakeet_vocab.json}`.
- Added compiled-bundle checks for `model.mil`, `metadata.json`, and `coremldata.bin` inside every required `.mlmodelc` directory.
- Added diagnostics that distinguish not-installed, missing artifacts, malformed Core ML bundles, and raw NVIDIA NeMo/Transformers source markers.
- Added FluidAudio load validation after download and before setting `isInstalled = true`; failed validation never reports a false-ready model.
- Added a safe force-repair action for incomplete or wrong-format selected folders.
- Updated `ParakeetTranscriptionEngine` to load the selected variant, use its decoder-layer metadata, invalidate cached sessions on variant changes, and preserve per-utterance decoder state.
- Updated Models Settings and the menu-bar popover to display the selected variant, provenance, validation state, repair action, and canonical folder.
- Preserved WhisperKit model discovery, import, selection, preload, and inference as a separate path. No raw NVIDIA folder is passed through WhisperKit.
- Added deterministic tests for v2/v3 persistence, exact v3 missing-artifact diagnostics, complete v2 structural validation, raw NVIDIA source rejection, and variant forwarding to the session factory.

## Behavioral boundary

Parakeet v2 and v3 remain local batch engines over VoiceFlow’s finalized audio file. They are not true live-streaming engines. FluidAudio streaming/EOU models are separate and are not enabled by this change. Normal microphone audio and ordinary local transcription remain on-device; only explicitly enabled AI processing can send post-transcription text to the configured provider.

A direct download of either NVIDIA URL is not a valid VoiceFlow Parakeet installation. Users must download the matching FluidInference Core ML conversion through VoiceFlow’s Parakeet Download action. The app does not attempt to convert NeMo/PyTorch/Transformers checkpoints, rename folders, or bypass Core ML validation.

## Verification

The focused Parakeet suite passes 8 tests with zero failures. An unsigned Debug app build succeeds with FluidAudio linked. The corrected behavior has not been validated with a real multi-gigabyte model download, real Parakeet inference, a microphone session, or TextEdit injection in this change; those remain manual Apple Silicon checks. The observed existing partial cache is expected to report missing artifacts until the user selects Repair or downloads the supported FluidInference conversion.

## References

[1]: https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3 "NVIDIA Parakeet TDT v3 upstream model"
[2]: https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2 "NVIDIA Parakeet TDT v2 upstream model"
[3]: https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml "FluidInference Parakeet TDT v3 Core ML conversion"
[4]: https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml "FluidInference Parakeet TDT v2 Core ML conversion"
[5]: https://github.com/FluidInference/FluidAudio "FluidAudio Swift SDK"

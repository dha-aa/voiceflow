# Specification Change 016 — Parakeet Partial-Bundle Diagnostics

## Summary

This change fixes the exact validation error reproduced from the Models screenshot. The local Parakeet cache contained only a partial `Decoder.mlmodelc` directory with an `analytics/coremldata.bin` partial artifact, while `Encoder.mlmodelc`, `JointDecisionv3.mlmodelc`, `Preprocessor.mlmodelc`, and `parakeet_vocab.json` were absent. The previous validator returned only the top-level missing-artifact list and hid the fact that the existing Decoder bundle was malformed.

## Test-first verification

Before changing implementation code, the unchanged full suite was run successfully with 142 tests and zero failures. A new regression fixture was then added for the observed partial compiled bundle and run against the unchanged validator. It failed because the message omitted both `Decoder.mlmodelc` and the missing compiled contents such as `model.mil`.

The validator was then changed minimally to preserve the existing status cases for single-category failures while adding a combined incomplete status when both required artifacts are absent and an existing compiled bundle is malformed. The regression test passed after the change, followed by a full suite run with 143 tests and zero failures.

## Behavior after the fix

The Models UI now reports both categories in one diagnostic, for example:

```text
Incomplete model. Missing: Encoder.mlmodelc, JointDecisionv3.mlmodelc, Preprocessor.mlmodelc, parakeet_vocab.json. Core ML issues: Decoder.mlmodelc missing model.mil, metadata.json, coremldata.bin.
```

The model remains not ready. Users should use **Repair** or remove the incomplete selected Parakeet cache and download the supported FluidInference Core ML conversion again. The validator does not accept a partial compiled bundle, rename it, or mark it installed.

## Scope and non-goals

This is a diagnostics and validation correction only. It does not alter WhisperKit model management, Parakeet v2/v3 loader parameters, the local-only inference boundary, or the unsupported status of raw NVIDIA NeMo/Transformers repositories. Real model download and inference remain manual Apple Silicon checks.

# Specification Change 003 — Custom WhisperKit Model Folder Import

## Status

Implemented in the VoiceFlow macOS application. This change adds a native Settings flow for importing the registered Oriserve Hindi/Hinglish WhisperKit Core ML model from a local folder without changing the audio-recording, transcription-coordination, or text-injection architecture.

## User-facing behavior

The Models settings pane now provides an **Import Model** button. The button opens the native macOS folder picker and accepts the local folder:

```text
Oriserve_Whisper-Hindi2Hinglish-Prime_889MB
```

The selected folder is imported only when it contains the required WhisperKit Core ML components directly inside it:

```text
MelSpectrogram.mlmodelc
AudioEncoder.mlmodelc
TextDecoder.mlmodelc
```

The UI displays import and validation progress and reports invalid-folder, duplicate-install, validation, and load failures through the existing model-action error alert.

## Model identity

VoiceFlow keeps a stable app-facing identifier separate from the model’s WhisperKit identity:

| Purpose | Value |
|---|---|
| VoiceFlow selection ID | `hinglish` |
| Display name | `Hindi/Hinglish` |
| Hugging Face repository | `nitinh/whisperkit-hinglish-coreml` |
| WhisperKit model ID | `Oriserve_Whisper-Hindi2Hinglish-Prime_889MB` |
| Folder name | `Oriserve_Whisper-Hindi2Hinglish-Prime_889MB` |
| Recommended decoding language | `en` |

The stable `hinglish` ID is persisted in `selectedWhisperModelId`. Before constructing a WhisperKit session, `TranscriptionEngine` maps that ID to the full Oriserve model ID.

## Managed storage

The importer copies the source into VoiceFlow’s repository-aware managed directory:

```text
~/Library/Application Support/dha-aa.voiceflow/models/models/nitinh/whisperkit-hinglish-coreml/Oriserve_Whisper-Hindi2Hinglish-Prime_889MB/
```

The source folder is not used directly for runtime inference. VoiceFlow owns and validates the managed copy so selection, deletion, preloading, and model loading use one stable path.

## Safety and validation contract

The import operation follows this sequence:

```text
Choose folder
→ Verify folder name and directory type
→ Create repository-local staging directory
→ Copy model folder into staging
→ Validate Core ML components and exact folder identity
→ Run optional real WhisperKit load validation
→ Move staged folder into final managed location
→ Refresh installed-model state
```

The importer rejects source symlinks, incorrect folder names, missing components, invalid paths, duplicate installations, and failed WhisperKit load validation. It never exposes a partial staging directory as an installed model. Temporary staging data is removed on both success and failure.

A configured `WhisperKitModelLoadValidator` receives the full remote model ID and exact staged folder. The current live validation therefore tests the same model identity and folder that later transcription will use.

## Existing model compatibility

Standard Argmax models continue to use the existing convention:

```text
<downloadBase>/models/argmaxinc/whisperkit-coreml/openai_whisper-<variant>/
```

Custom models use their registered repository namespace and folder name. The change does not loosen standard validation globally or accept arbitrary directories.

## Tests and validation

Focused tests cover:

- Importing a structurally valid custom model folder.
- Resolving the imported folder through `resolveInstalledModel(id: "hinglish")`.
- Preserving the `Hindi/Hinglish` display name.
- Mapping `hinglish` to `Oriserve_Whisper-Hindi2Hinglish-Prime_889MB` before WhisperKit session creation.
- Rejecting a folder with the wrong name.
- Existing standard model discovery, selection, caching, download, and deletion behavior.

The focused ModelManager and TranscriptionEngine test groups pass with **25 tests and 0 failures**. The real local Oriserve model was separately loaded through WhisperKit using its exact folder and full model ID; initialization succeeded in approximately 187 seconds. No application source or model files were modified by that direct load test.

## Privacy

The import flow is local-only. It copies model files within the Mac’s filesystem and does not upload model data. Logs contain only safe metadata such as model IDs, paths, status categories, and validation outcomes. Audio, transcription text, injected text, and clipboard contents remain excluded from diagnostics.

## Source files

| File | Change |
|---|---|
| `voiceflow/Core/Transcription/ModelManager.swift` | Custom model definition, repository-aware resolution, import staging, validation, promotion, and error handling. |
| `voiceflow/Core/Transcription/TranscriptionEngine.swift` | Maps the stable custom selection ID to the full WhisperKit model ID. |
| `voiceflow/UI/Settings/ModelsSettingsView.swift` | Native folder picker, import progress, and error presentation. |
| `voiceflow/UI/Settings/ModelDownloadCoordinator.swift` | Duplicate-import error message mapping. |
| `voiceflowTests/Transcription/ModelManagerTests.swift` | Custom import and invalid-folder coverage. |
| `voiceflowTests/Transcription/TranscriptionEngineTests.swift` | Custom alias-to-WhisperKit-ID coverage. |
| `specs/spec_03_transcription.md` | Custom repository, storage, validation, import, and loading contract. |
| `specs/spec_06_settings_and_model_management.md` | Import Model UI behavior and acceptance criteria. |
| `README.md` | Local custom model import usage and storage layout. |

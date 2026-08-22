# SPEC 03 — WhisperKit Transcription Engine

## 1. Purpose

This specification builds the transcription engine — the component that receives a recorded audio file and returns transcribed text using a locally downloaded WhisperKit model.

By the end of this spec, VoiceFlow can take the audio file produced by Spec 02 and produce clean, formatted text — all without any UI involvement. The transcription pipeline must be independently testable from the command line or unit tests using a test audio file.

---

## 2. Scope

- Implement `ModelManager` to discover, list, download, and delete locally stored WhisperKit models.
- Implement `TranscriptionEngine` to load a WhisperKit model and transcribe an audio file.
- Implement `TextProcessor` to normalize and clean the raw transcription output.
- Integrate with `RecordingCoordinator.onRecordingComplete` so that transcription starts automatically when a recording finishes.
- Drive `AppStateManager` state transitions:
  - Transcription starts → state is already `.processing` (set by Spec 02)
  - Transcription completes → `transition(to: .injecting)`
  - Error → `transition(to: .error(...))`
- Expose the final processed text via a stable interface that Spec 04 consumes.

---

## 3. Out of Scope

Do NOT implement any of the following in this specification:

- Text injection into other applications (Spec 04).
- The recording overlay or any UI (Spec 05).
- Settings UI for model selection (Spec 06).
- Fn key monitoring or audio recording (Spec 02 — already complete).
- Real-time/streaming transcription (not required for push-to-talk).
- Speaker diarization or TTS (SpeakerKit, TTSKit).

---

## 4. Dependencies

**Spec 01 and Spec 02 must be complete and verified before starting this spec.**

Required from Spec 01:
- `AppState` enum — `.processing`, `.injecting`, `.error` cases.
- `AppStateManager.transition(to:)`.
- WhisperKit linked as a Swift Package dependency.

Required from Spec 02:
- `RecordingCoordinator.onRecordingComplete: ((URL, NSRunningApplication?) -> Void)?` — stable interface.
- Audio file format: 16,000 Hz, mono, PCM — WhisperKit-compatible.
- `AppStateManager` is in `.processing` state when transcription should begin.

**Framework dependencies:**
- `WhisperKit` (already linked in Spec 01).
- `Foundation` — file management, temporary files.

---

## 5. Implementation Requirements

### 5.1 Model Manager

Implement `ModelManager` in `Core/Transcription/ModelManager.swift`.

Responsibilities:
- **Fetch the remote model catalog** using `WhisperKit.fetchAvailableModels(from:matching:)`, which queries the live `argmaxinc/whisperkit-coreml` HuggingFace repository. Do not hardcode the model list.
- **Fetch device recommendations** using `WhisperKit.recommendedRemoteModels(from:)` to know which model is best for the current device.
- **Discover locally installed models** by checking the WhisperKit model cache directory on disk.
- Return a list of `WhisperModel` value types, each containing:
  - `id: String` — the variant identifier (e.g., `"large-v3-v20240930_626MB"`), with the `openai_whisper-` prefix stripped from the remote ID.
  - `displayName: String` — a human-readable name derived from the variant string at runtime (replace hyphens/underscores with spaces, capitalize). Do not use a static lookup table.
  - `sizeOnDisk: Int64?` — computed from disk for downloaded models via `FileManager`; `nil` for models not yet downloaded.
  - `isDownloaded: Bool` — determined by checking whether the model directory exists in the WhisperKit cache.
  - `isActive: Bool` — whether this is the currently selected model.
  - `isRecommended: Bool` — whether WhisperKit recommends this model for the current device.
- Persist the user's selected model identifier using `UserDefaults`.
- Download a model using `WhisperKit.download(variant:from:progressCallback:)`.
- Delete a downloaded model by removing its directory from disk.

```swift
struct WhisperModel: Identifiable, Equatable {
    let id: String              // variant name, e.g. "large-v3-v20240930_626MB"
    let displayName: String     // derived at runtime from id
    let sizeOnDisk: Int64?      // bytes on disk; nil if not downloaded
    let isDownloaded: Bool
    let isRecommended: Bool
    var isActive: Bool
}

@Observable
final class ModelManager {
    private(set) var availableModels: [WhisperModel] = []
    private(set) var selectedModelId: String?
    private(set) var isLoading: Bool = false

    func refreshModels() async throws { ... }  // fetches remote catalog + checks disk
    func selectModel(id: String) { ... }
    func downloadModel(id: String, progress: @escaping (Double) -> Void) async throws { ... }
    func deleteModel(id: String) throws { ... }
}
```

`refreshModels()` implementation steps:
1. Call `WhisperKit.fetchAvailableModels(from: "argmaxinc/whisperkit-coreml", matching: ["*"])` to get the remote list.
2. Call `WhisperKit.recommendedRemoteModels(from: "argmaxinc/whisperkit-coreml")` to get device recommendations.
3. For each remote model ID, strip the `openai_whisper-` prefix to get the variant name.
4. Check which variants are downloaded by scanning the WhisperKit model directory on disk (see §5.1.1 below).
5. Compute `sizeOnDisk` using `FileManager` for downloaded models.
6. Build the `[WhisperModel]` array and publish it.

#### 5.1.1 Model Storage Location

By default, WhisperKit drops models into `~/Documents/huggingface/`. **We do not want this.** Models must be stored within the application's sandbox/data directory.

You must explicitly set the `downloadBase` URL when interacting with `WhisperKit` to point to the app's Application Support directory:

```swift
static var appModelsDirectory: URL {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let bundleID = Bundle.main.bundleIdentifier ?? "com.voiceflow"
    let modelsDir = appSupport.appending(component: bundleID).appending(component: "models")
    
    // Ensure the directory exists
    try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
    
    return modelsDir
}
```

When calling WhisperKit APIs, always pass this `appModelsDirectory` as the `downloadBase`:

**Fetching Available Models:**
```swift
let remoteModelIds = try await WhisperKit.fetchAvailableModels(
    from: "argmaxinc/whisperkit-coreml",
    matching: ["*"],
    downloadBase: Self.appModelsDirectory
)
```

**Downloading a Model:**
```swift
let localURL = try await WhisperKit.download(
    variant: variantId,
    downloadBase: Self.appModelsDirectory,
    from: "argmaxinc/whisperkit-coreml",
    progressCallback: { progress in /* ... */ }
)
```

**Initializing the Engine:**
```swift
// In TranscriptionEngine.swift
let config = WhisperKitConfig(model: selectedModelId, downloadBase: ModelManager.appModelsDirectory)
let pipe = try await WhisperKit(config)
```

**Checking if a model is downloaded:**
The downloaded models will be stored in `appModelsDirectory` under `models--argmaxinc--whisperkit-coreml/snapshots/<commit-hash>/openai_whisper-<variantId>`.

```swift
static var whisperKitModelBase: URL {
    return appModelsDirectory
        .appending(component: "models--argmaxinc--whisperkit-coreml")
        .appending(component: "snapshots")
}

func isModelDownloaded(variantId: String) -> Bool {
    let snapshotsDir = Self.whisperKitModelBase
    guard let snapshots = try? FileManager.default.contentsOfDirectory(
        at: snapshotsDir, includingPropertiesForKeys: nil
    ) else { return false }
    
    return snapshots.contains { snapshot in
        let modelDir = snapshot.appending(component: "openai_whisper-\(variantId)")
        return FileManager.default.fileExists(atPath: modelDir.path)
    }
}
```

> **Note:** The underlying Hub library still manages a deduplication cache in `~/.cache/huggingface/`. Do not interact with that directory directly; let the library manage it.



### 5.2 Transcription Engine

Implement `TranscriptionEngine` in `Core/Transcription/TranscriptionEngine.swift`.

Responsibilities:
- Initialize WhisperKit with the currently selected model.
- Cache the initialized `WhisperKit` instance — do not re-initialize for every transcription.
- Reinitialize if the selected model changes.
- Accept an audio file `URL` and return a `String` transcription.
- Handle model-not-installed and model-load-failure errors.

```swift
final class TranscriptionEngine {
    init(modelManager: ModelManager) { ... }

    // Loads the selected model if not already loaded
    func prepare() async throws { ... }

    // Transcribes audio at the given URL; returns the transcribed text
    func transcribe(audioURL: URL) async throws -> String { ... }
}
```

WhisperKit initialization:

```swift
// Use the model path from ModelManager
let pipe = try await WhisperKit(WhisperKitConfig(model: selectedModelId))
```

Transcription:

```swift
let results = try await pipe.transcribe(audioPath: audioURL.path)
let rawText = results.map(\.text).joined(separator: " ")
```

Error mapping:
- If no model is selected or installed → throw / call `AppStateManager.transition(to: .error(.modelNotInstalled))`.
- If WhisperKit initialization fails → `transition(to: .error(.modelFailedToLoad))`.
- If transcription returns empty string → `transition(to: .error(.noAudioDetected))`.
- If transcription throws → `transition(to: .error(.transcriptionFailed))`.

### 5.3 Text Processor

Implement `TextProcessor` in `Core/Transcription/TextProcessor.swift`.

Responsibilities:
- Normalize whitespace: collapse multiple spaces, trim leading/trailing whitespace.
- Remove filler artifacts that WhisperKit sometimes produces (e.g., `[BLANK_AUDIO]`, `(inaudible)`).
- Preserve the user's intended wording — do not paraphrase or rewrite.
- Return the cleaned string.

```swift
struct TextProcessor {
    func process(_ rawText: String) -> String { ... }
}
```

This must be a pure function with no side effects — input in, output out. Easy to unit test.

### 5.4 Transcription Coordinator

Implement `TranscriptionCoordinator` in `Core/Transcription/TranscriptionCoordinator.swift`.

This class wires together `TranscriptionEngine`, `TextProcessor`, and `AppStateManager`.

```swift
final class TranscriptionCoordinator {
    init(
        stateManager: AppStateManager,
        engine: TranscriptionEngine,
        processor: TextProcessor
    ) { ... }

    // Called by RecordingCoordinator.onRecordingComplete
    func transcribe(audioURL: URL, targetApp: NSRunningApplication?) async { ... }

    // Spec 04 connects to this
    var onTranscriptionComplete: ((String, NSRunningApplication?) -> Void)?
}
```

Internal logic:
1. Receive `audioURL` and `targetApp`.
2. State should already be `.processing` (set by Spec 02).
3. Call `engine.transcribe(audioURL:)`.
4. Call `processor.process(rawText)`.
5. Call `stateManager.transition(to: .injecting)`.
6. Call `onTranscriptionComplete(finalText, targetApp)`.
7. On any error, call `stateManager.transition(to: .error(...))`.

### 5.5 Wiring into App

Connect `RecordingCoordinator` and `TranscriptionCoordinator` at the app entry point:

```swift
recordingCoordinator.onRecordingComplete = { [weak transcriptionCoordinator] audioURL, targetApp in
    Task {
        await transcriptionCoordinator?.transcribe(audioURL: audioURL, targetApp: targetApp)
    }
}
```

---

## 6. Files and Components

### Files to create

| File | Purpose |
|------|---------|
| `Core/Transcription/ModelManager.swift` | Model discovery, selection, download, delete |
| `Core/Transcription/TranscriptionEngine.swift` | WhisperKit initialization and transcription |
| `Core/Transcription/TextProcessor.swift` | Raw text normalization and cleanup |
| `Core/Transcription/TranscriptionCoordinator.swift` | Wires engine + processor + state transitions |

### Files that may be modified

| File | Permitted change |
|------|----------------|
| `App/VoiceFlowApp.swift` | Instantiate and wire `TranscriptionCoordinator` |
| `App/AppDelegate.swift` | Same |

### Files that must NOT be modified

| File | Reason |
|------|--------|
| `Core/State/AppState.swift` | Stable from Spec 01 |
| `Core/State/AppStateManager.swift` | Stable from Spec 01 |
| `Core/Audio/` | Stable from Spec 02 |

### Reserved (do not create yet)

- `Core/Injection/` — Spec 04
- `UI/Overlay/` — Spec 05
- `UI/Settings/` — Spec 06

---

## 7. Tests

Write and run these tests before marking this spec complete.

### Unit Tests: `TextProcessorTests.swift`

```
test_textProcessor_trimsLeadingTrailingWhitespace
  Input: "  hello world  "
  Expected: "hello world"

test_textProcessor_collapsesMultipleSpaces
  Input: "hello   world"
  Expected: "hello world"

test_textProcessor_removesBlankAudioArtifact
  Input: "[BLANK_AUDIO]"
  Expected: ""

test_textProcessor_removesInaudibleMarker
  Input: "hello (inaudible) world"
  Expected: "hello world"

test_textProcessor_preservesNormalText
  Input: "The quick brown fox jumps over the lazy dog."
  Expected: "The quick brown fox jumps over the lazy dog."

test_textProcessor_handlesEmptyString
  Input: ""
  Expected: ""
```

### Unit Tests: `ModelManagerTests.swift`

```
test_modelManager_initialState_noModelsLoaded
  Create ModelManager. Assert availableModels is empty before refreshModels() is called.

test_modelManager_selectModel_updatesSelectedModelId
  Call selectModel(id: "tiny"). Assert selectedModelId == "tiny".

test_modelManager_selectModel_persistsThroughUserDefaults
  Call selectModel(id: "tiny"). Create a new ModelManager instance.
  Assert selectedModelId == "tiny".
```

### Integration Tests: `TranscriptionEngineTests.swift`

> These tests require a downloaded WhisperKit model. Use `"tiny.en"` for speed during development.

```
test_transcriptionEngine_transcribes_testAudioFile
  1. Download or use a pre-downloaded "tiny.en" model.
  2. Use a known test WAV file with the phrase "hello world".
  3. Call transcribe(audioURL:).
  4. Assert the result contains "hello" or "world" (case-insensitive).

test_transcriptionEngine_returnsError_forSilentAudio
  Use a WAV file containing only silence.
  Assert the result is empty or an .noAudioDetected error is thrown/reported.
```

### Integration Test: Full Core Pipeline

```
test_fullPipeline_recordingToTranscription
  1. Use a pre-recorded test WAV file (16,000 Hz, mono) with spoken phrase "testing one two three".
  2. Call TranscriptionCoordinator.transcribe(audioURL:).
  3. Assert onTranscriptionComplete is called.
  4. Assert the returned text contains "testing" or "one two three".
  5. Assert AppStateManager.currentState == .injecting after completion.
```

### Manual Verification

```
- Build and run the app.
- Hold Fn. Speak a sentence. Release Fn.
- Watch the console. Confirm:
  - "State → recording" (Spec 02)
  - "State → processing"
  - "Transcription complete: <your spoken text>"
  - "State → injecting"
- Confirm the transcription is readable and matches what was spoken.
- Confirm no crash or hang occurs.
```

---

## 8. Acceptance Criteria

All of the following must be true before this spec is complete:

- [ ] `TextProcessor` unit tests all pass.
- [ ] `ModelManager` correctly discovers at least one downloaded model (or reports none installed).
- [ ] `TranscriptionEngine` successfully transcribes a known test audio file.
- [ ] `TranscriptionEngine` reuses a cached WhisperKit instance (does not re-initialize every call).
- [ ] Full pipeline integration test passes (audio URL in → transcribed text out).
- [ ] Console shows correct state transitions: `.processing` → `.injecting` on success.
- [ ] Error cases produce correct `.error(...)` state transitions.
- [ ] Manual push-to-talk test produces a readable transcription.
- [ ] The `TranscriptionCoordinator.onTranscriptionComplete` interface is stable.

---

## 9. Completion Gate

**This spec is NOT complete until:**

1. All acceptance criteria are checked off.
2. All unit tests pass.
3. Integration test passes with a real audio file.
4. Manual push-to-talk test produces recognizable transcription.
5. `TranscriptionCoordinator.onTranscriptionComplete` interface is stable and ready for Spec 04.
6. No known errors or test failures remain.

**Do not proceed to Spec 04 until this gate passes.**

---

## 10. Handoff to Spec 04

Spec 04 receives these stable, verified components:

| Component | What Spec 04 can rely on |
|-----------|--------------------------|
| `TranscriptionCoordinator.onTranscriptionComplete` | Called with final processed `String` and `NSRunningApplication?` after every recording |
| `AppStateManager` | In `.injecting` state when injection should begin |
| `TextProcessor` | Stable pure function; text is already normalized |
| `ModelManager` | Exposes `selectedModelId` and `availableModels` |

Spec 04 will connect to `TranscriptionCoordinator.onTranscriptionComplete` and inject the final text into the focused application.

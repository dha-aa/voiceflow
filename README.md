# VoiceFlow

VoiceFlow is a privacy-first native macOS menu-bar dictation application. Hold **Fn** to record, release it to transcribe locally with WhisperKit or Parakeet TDT v2/v3, and inject the resulting text into the focused text field. Audio and dictated content remain on the Mac during normal operation; VoiceFlow does not send microphone audio or transcription text to a remote service.

> **Current distribution note:** VoiceFlow supports an unsigned DMG for development or private sharing. A signed and notarized DMG is also supported when Apple Developer credentials are configured. Unsigned applications can trigger macOS Gatekeeper warnings.
>
>
>
 🎥 Watch the full build:
## 🎥 Video

[![Watch the video](https://img.youtube.com/vi/eOIdjLaHOHY/maxresdefault.jpg)](https://youtu.be/eOIdjLaHOHY)

## Features

| Capability | Description |
|---|---|
| Push-to-talk | A sustained Fn hold starts one recording session; releasing Fn stops it. A brief tap does not intentionally start dictation. |
| Local transcription | WhisperKit or Parakeet TDT v2/v3 runs the selected Core ML model locally. The app reuses a loaded engine session when the selected engine/model has not changed. Parakeet v2 is English-focused; v3 is multilingual and batch-oriented. |
| Local audio storage | Completed recordings are stored as UUID-named 16 kHz mono PCM float32 WAV files in `~/Library/Application Support/dha-aa.voiceflow/audio/`. General settings control retention from instant deletion through 5 hours, 3 days, 7 days, or never delete, and provide Delete All Audio. |
| Clipboard fallback | If no active text input is available, VoiceFlow still transcribes locally and copies the final text to the macOS clipboard instead of treating output as an injection failure. |
| Snippets | Settings → Snippets provides local Name/Trigger/Value CRUD. Trigger phrases expand naturally, case-insensitively, before injection; stored values never enter AI requests or logs. |
| Claude commands | Optional BYOK Claude processing is triggered only when a transcript starts with the user-configured prefix; normal dictation remains local. When selected text is available, only the selection and instruction are sent, and the result replaces that selection. |
| Grammar Fix | Optional Claude grammar and punctuation correction applies only to ordinary speech without the configured AI prefix; AI commands always take precedence. |
| Model management | Settings provides engine-aware model availability, Parakeet v2/v3 download/status, WhisperKit download progress, local Core ML model-folder import, selection, installation detection, validation, deletion protection, and Finder navigation. Parakeet validation is separate from WhisperKit and rejects raw NVIDIA NeMo/Transformers repositories. |
| Readiness gating | VoiceFlow preloads the selected model and waits for it to be ready before recording begins. |
| Text injection | The focused application is captured when recording begins. Accessibility-based insertion is used for ordinary apps and leaves the caret at the end; Terminal-family apps use a temporary clipboard plus frontmost Command-V paste, move to end-of-line, then restore the previous clipboard. |
| Recording overlay | A compact floating HUD communicates Loading model, Listening, Processing, `Using Claude...` or `Using ChatGPT...` for AI requests, Done, and error states. |
| Menu-bar status | The menu-bar icon reflects idle, recording, processing, completion, and error states. The idle identity mark is a native template image for Light and Dark Mode contrast. |
| Completion feedback | General settings can enable a short completion sound and select Tink, Pop, or Glass. It is disabled by default and only plays after successful text injection or clipboard copy. |
| Settings | General, AI, Models, Snippets, and About sections are available from the menu-bar application. General includes permissions, completion feedback, audio retention, and Delete All Audio. |
| Privacy-safe diagnostics | Structured logs contain lifecycle metadata such as model identifiers, paths, durations, byte counts, and error categories—not audio, prompts, responses, transcripts, or inserted text. |

## Expected interaction

```text
Fn held
  → model ready / Loading model
  → Listening
Fn released
  → Processing
  → local transcription
  → optional AI processing
  → local snippet expansion
  → Using Claude... / Using ChatGPT... (only for an explicit configured AI command)
  → text injection or Copied to Clipboard
  → Done / Copied to Clipboard
  → Idle
```

If microphone permission, Accessibility permission, model installation, transcription, or injection fails, VoiceFlow shows an actionable error and returns the pipeline to a safe state.

### AI command and Grammar Fix precedence

VoiceFlow detects the configured AI prefix immediately after local transcription. A matching prefix always takes precedence over Grammar Fix: VoiceFlow removes the prefix, sends only the remaining request to Claude, and does not grammar-correct the command first. When no AI prefix is present and **Fix Grammar & Punctuation** is enabled in **Settings → AI**, VoiceFlow sends the ordinary transcript to Claude with a correction-only system instruction and injects only Claude’s corrected text. When both features are off, the local transcript is injected unchanged.

| AI prefix detected | Grammar Fix | Result |
|---|---|---|
| Yes | On | Send the prefix remainder to Claude as an AI request; do not apply Grammar Fix first. |
| Yes | Off | Send the prefix remainder to Claude as an AI request. |
| No | On | Send the complete ordinary transcript to Claude for grammar, spelling, capitalization, and punctuation correction only. |
| No | Off | Keep the transcript local and inject it unchanged. |

### Local snippets

Open **Settings → Snippets** to create a reusable entry with a name, trigger phrase, and value. Snippets work without a special voice command and can appear naturally inside a sentence. For example, configuring `my email` with the value `user@gmail.com` changes:

> You can contact me at my email address.

into:

> You can contact me at user@gmail.com address.

Matching is case-insensitive, respects whole-phrase boundaries, supports multi-word triggers, and prefers the longer trigger when configured triggers overlap. Snippets are expanded locally after optional AI processing and immediately before injection. Their values are stored as local application data in `UserDefaults`; they are not sent to Claude, ChatGPT, or any other provider, and they are not written to diagnostics. Snippets are not a secure secret vault and should not be used for passwords or credentials.

## Requirements

VoiceFlow currently targets **macOS 14.0 or later** and is built with the native SwiftUI/AppKit stack. Development requires the full Xcode installation, not only Command Line Tools. The project uses Swift Package Manager through the Xcode project and depends on [Argmax OSS Swift](https://github.com/argmaxinc/argmax-oss-swift) for WhisperKit and [FluidAudio](https://github.com/FluidInference/FluidAudio) 0.15.6 for Parakeet TDT v2/v3.

A real dictation session requires microphone permission and Accessibility or Input Monitoring permission as requested by macOS. Text injection into another application cannot be verified from a build-only test; it must be tested manually with a permitted target application. Completed recordings are stored locally in the VoiceFlow audio folder under Application Support, and their retention is controlled from General Settings.


## Getting started

Clone the repository and open the Xcode project:

```bash
git clone git@github.com:dha-aa/voiceflow.git
cd voiceflow
open voiceflow.xcodeproj
```

Select the `voiceflow` scheme and run the app from Xcode. VoiceFlow appears as a menu-bar application rather than a normal Dock application. On the first launch, the onboarding window explains the workflow and presents Microphone and Accessibility permissions one at a time before asking macOS to display each system prompt. Screen Recording is explained as a future screen-context capability and is not requested by the current version. If a permission is skipped or denied, VoiceFlow remains usable where possible; unresolved permissions can later be requested or opened in **Settings → General → Permissions**.

Open the menu-bar popover and go to **Settings → General** to choose Audio Retention or use **Delete All Audio**. Go to **Settings → Models**. Select an installed model, download one, or use **Import Model** to choose a local WhisperKit Core ML model folder such as `Oriserve_Whisper-Hindi2Hinglish-Prime_889MB` from Finder. VoiceFlow validates the imported folder, verifies it can load through WhisperKit, and copies it into the managed model directory before showing it as installed. Choose **WhisperKit** or **Parakeet TDT v2/v3** in **Settings → Models**. WhisperKit uses the canonical model root below. Parakeet uses a separate FluidAudio cache and is currently supported on Apple Silicon only. Completed microphone recordings are stored separately from models in the local VoiceFlow audio folder:

```text
~/Library/Application Support/dha-aa.voiceflow/audio
```

VoiceFlow stores its canonical WhisperKit model root under:

```text
~/Library/Application Support/dha-aa.voiceflow/models
```

WhisperKit’s downloaded repository layout is nested below that root under `models/argmaxinc/whisperkit-coreml/openai_whisper-<variant>`. Registered custom models use their own repository namespace and exact folder name, for example `models/nitinh/whisperkit-hinglish-coreml/Oriserve_Whisper-Hindi2Hinglish-Prime_889MB`. VoiceFlow validates the exact model folder and confirms that WhisperKit can load the required model components before marking a model as installed.

Parakeet downloads use FluidAudio’s cache folder names under `~/Library/Application Support/dha-aa.voiceflow/models/fluidaudio/parakeet-tdt-0.6b-v3` or `parakeet-tdt-0.6b-v2`. The supported sources are the [FluidInference v3 Core ML conversion](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml) and [FluidInference v2 Core ML conversion](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml). The upstream [NVIDIA v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3) and [NVIDIA v2](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2) repositories contain NeMo/Transformers artifacts such as `.nemo`, `model.safetensors`, or GGUF files; VoiceFlow rejects them because they are not FluidAudio Core ML bundles. A model is shown as installed only after the exact required bundles are present and `AsrModels.load` succeeds.

## Repository layout

| Path | Responsibility |
|---|---|
| `voiceflow/App/` | Application lifecycle and dependency composition. |
| `voiceflow/Core/Audio/` | Fn monitoring, microphone capture, recording coordination, and persistent local WAV storage under the app audio directory. |
| `voiceflow/Core/Transcription/` | Engine-neutral local transcription, WhisperKit and Parakeet model lifecycle, text processing, and cached-session reuse. |
| `voiceflow/Core/Injection/` | Focused-app capture, Accessibility insertion, keyboard-event fallback, and completion feedback. |
| `voiceflow/Core/State/` | Explicit application states and state transitions. |
| `voiceflow/Core/LLM/` | Provider-neutral AI requests, reusable prompt modes, optional screen context, Claude BYOK client, model discovery, custom-prefix routing, and Grammar Fix. |
| `voiceflow/Core/Logging/` | Privacy-safe structured logging. |
| `voiceflow/Core/Permissions/` | Microphone, Accessibility, and future screen-context permission status and requests. |
| `voiceflow/UI/MenuBar/` | Menu-bar item, template icon behavior, and popover presentation. |
| `voiceflow/UI/Overlay/` | Recording HUD, state mapping, animation, and waveform display. |
| `voiceflow/UI/Onboarding/` | First-launch welcome, sequential permissions, skip/denial handling, and setup completion. |
| `voiceflow/UI/Settings/` | General, AI, Models, Snippets, About, download coordination, and Settings window behavior. |
| `voiceflowTests/` | Unit, integration, model lifecycle, injection, overlay, and settings regression tests. |
| `spec_changes/` | Sequential implementation change records, including the local Snippets and audio-storage changes. |
| `scripts/release.sh` | Shared local release script for signed or unsigned DMGs. |
| `.github/workflows/release.yml` | Tag-triggered and manually triggered CI distribution workflow. |
| `docs/testing.md` | Automated and manual verification procedures. |
| `docs/release.md` | Release modes, artifact handling, credentials, and Gatekeeper guidance. |

## Privacy and security model

VoiceFlow’s normal recording-to-injection path is local. Network access is used for model catalog and model downloads, not for sending captured audio for remote transcription. Explicit, user-enabled Claude processing is the only dictated-text exception: a matching custom prefix sends only the command remainder, while Grammar Fix sends the complete ordinary transcript only when its toggle is enabled and no AI prefix matches. Do not add telemetry, remote transcription, or transcript-bearing diagnostics without a separate privacy review.

Logs must remain metadata-only. Safe examples include model IDs, model paths, audio file identifiers, file sizes, durations, state names, process identifiers, and error categories. Do not log microphone samples, audio contents, raw transcripts, inserted text, clipboard contents, or secret environment variables.

WAV recordings remain local and are not uploaded automatically. General Settings controls whether recordings are deleted instantly, after 5 hours, after 3 days, after 7 days, or never automatically; Delete All Audio removes managed recordings manually. Snippet values are also local application data; snippet expansion is synchronous and local, and configured values are never sent to Claude, ChatGPT, or any other provider. If no active text input exists, VoiceFlow copies the final output to the general clipboard without logging its contents.

The app is intentionally non-sandboxed because the current implementation uses global Fn monitoring and cross-process Accessibility text injection. The Release target enables Hardened Runtime and carries only the microphone entitlement required by the app’s current design.

### AI settings and optional Claude commands

Open **Settings → AI** to choose the default AI provider. Claude is currently the only implemented provider; ChatGPT is shown as a future provider and does not make OpenAI requests in this version. Provider clients use the same request shape, prompt modes, optional selected-text and screen-context slots, selected model, and direct-injection output contract. Enable Claude commands, set a custom command prefix, enter an Anthropic API key, and save it. The independent **Fix Grammar & Punctuation** toggle enables correction-only processing for ordinary speech without an AI prefix. After saving, the UI shows a masked value and **Configured** status with **Change API Key** and **Remove API Key** controls. VoiceFlow stores the key in the macOS Keychain, not in UserDefaults, source files, logs, or model files. The Claude model is selected per provider and can be entered manually or fetched from Anthropic with **Fetch available models**. The initial fallback is `claude-sonnet-5`; use a model ID available to your Anthropic account. Anthropic documents the model-list operation and direct Messages API request headers.[4] [5]

When enabled, a spoken transcript beginning with the configured custom prefix routes only the remaining instruction to Claude. If the preserved target application exposes selected text through Accessibility, VoiceFlow sends only that selected text plus the instruction and replaces the selection with Claude’s result; it does not invoke broader screen context in that case. The default prefix is `Claude`, but users can choose a phrase such as `Ask Claude`, `AI`, `@claude`, or `Jarvis`. For example, with the prefix `Claude`, `Claude, rewrite this politely` sends `rewrite this politely`; normal dictation without the prefix remains local unless Grammar Fix is enabled. If Grammar Fix is enabled and no prefix matches, VoiceFlow sends the complete ordinary transcript to Claude with a correction-only system prompt and injects the returned corrected text. AI-prefix detection always happens first, so Grammar Fix cannot modify an AI command before Claude receives it. Claude’s returned text is then sent through the existing injection path. Microphone audio and the ordinary local transcription remain local, but explicitly routed text is intentionally sent to Anthropic using the user’s own key. VoiceFlow logs only provider/model identifiers, character counts, durations, and error categories—not API keys, prompts, responses, audio, or injected text.

## Development commands

Run the complete XCTest suite from a full Xcode installation:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild \
  -project voiceflow.xcodeproj \
  -scheme voiceflow \
  -configuration Debug \
  -derivedDataPath /tmp/voiceflow-tests \
  -destination 'platform=macOS' \
  ONLY_ACTIVE_ARCH=YES \
  -only-testing:voiceflowTests \
  test \
  CODE_SIGNING_ALLOWED=NO
```

The current suite contains **186 tests** covering the recording stage, app audio-directory placement, retention policy and cleanup, pipeline coordination, model management, transcription session behavior, text injection, clipboard fallback, overlay state, provider-aware overlay status, onboarding permission flow, AI provider/model persistence, custom-prefix routing, Grammar Fix precedence, provider-neutral request handling, selected-text forwarding, broad-context suppression when selected text exists, no-selection fallback, optional screen-context forwarding, Claude model-list decoding, Parakeet session reuse and error mapping, persisted speech-engine selection, router dispatch, local Snippet CRUD and expansion, AI privacy protection for snippet values, and related regressions. See [`docs/testing.md`](docs/testing.md) for the full verification matrix.

Build a local unsigned app bundle into `build/` with the convenience script:

```bash
./scripts/buildapp.sh
./scripts/buildapp.sh --test --reveal
./scripts/buildapp.sh --open
```

Use `--release` for an unsigned Release configuration, `--clean` to remove only the known generated app output, and `--install` to copy the result to `/Applications/VoiceFlow.app` (administrator permission may be requested). The script keeps Xcode derived data temporary and does not create a signed or notarized artifact; for distribution DMGs, use [`scripts/release.sh`](scripts/release.sh).

### Continuous integration

Every pull request targeting `main`, every push to `main`, and manual CI runs execute the **CI Quality Gate** workflow. It validates the repository and workflow files, builds the Debug app without signing, and runs the complete XCTest suite. The workflow publishes its result directly to the pull request through GitHub Checks and the job summary. The protected `main` branch requires the `CI Quality Gate` status check, so a failing build, test, or quality check cannot be merged through the normal pull-request path.

For a credential-free local DMG build, use:

```bash
OUTPUT_DIR=/tmp/voiceflow-unsigned/dist \
DERIVED_DATA_DIR=/tmp/voiceflow-unsigned/derived-data \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
./scripts/release.sh --unsigned 1.0.0
```

For a signed and notarized local release, configure the credentials described in [`docs/release.md`](docs/release.md) and run:

```bash
./scripts/release.sh --check
./scripts/release.sh 1.0.0
```

## Git workflow

The default branch is `main`. Create topic branches for changes, run the relevant automated tests, and keep commits focused. Do not commit Xcode user state, generated derived data, DMGs, certificates, private keys, provisioning profiles, model files, or secret values. See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the contributor process.

## Known distribution limitation

The unsigned workflow can publish a DMG to GitHub Releases without Apple credentials. This is useful for development or private sharing, but macOS may display an unidentified-developer warning. A recipient can normally Control-click the app, choose **Open**, and confirm; if needed, use **System Settings → Privacy & Security → Open Anyway**. Signed and notarized distribution is recommended for broad public use.

## References

[1]: https://github.com/argmaxinc/argmax-oss-swift "Argmax OSS Swift"
[2]: https://developer.apple.com/documentation/security/customizing-the-notarization-workflow "Apple: Customizing the notarization workflow"
[3]: https://support.apple.com/en-gb/guide/mac-help/mh40616/mac "Apple Support: Safely open apps on Mac"
[4]: https://platform.claude.com/docs/en/manage-claude/authentication "Anthropic: Claude API authentication"
[5]: https://platform.claude.com/docs/en/api/models/list "Anthropic: List Models API"

# VoiceFlow

VoiceFlow is a privacy-first native macOS menu-bar dictation application. Hold **Fn** to record, release it to transcribe locally with WhisperKit, and inject the resulting text into the focused text field. Audio and dictated content remain on the Mac during normal operation; VoiceFlow does not send microphone audio or transcription text to a remote service.

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
| Local transcription | WhisperKit runs the selected Core ML model locally. The app reuses a loaded session when the selected model has not changed. |
| Claude commands | Optional BYOK Claude processing is triggered only when a transcript starts with `Claude`; normal dictation remains local. |
| Model management | Settings provides model availability, download progress, local Core ML model-folder import, selection, installation detection, validation, deletion protection, and Finder navigation. |
| Readiness gating | VoiceFlow preloads the selected model and waits for it to be ready before recording begins. |
| Text injection | The focused application is captured when recording begins. Accessibility-based insertion is attempted before keyboard-event fallback. |
| Recording overlay | A compact floating HUD communicates Loading model, Listening, Processing, Done, and error states. |
| Menu-bar status | The menu-bar icon reflects idle, recording, processing, completion, and error states. The idle identity mark is a native template image for Light and Dark Mode contrast. |
| Completion feedback | General settings can enable a short completion sound and select Tink, Pop, or Glass. It is disabled by default and only plays after successful injection. |
| Settings | General, AI, Models, and About sections are available from the menu-bar application. |
| Privacy-safe diagnostics | Structured logs contain lifecycle metadata such as model identifiers, paths, durations, byte counts, and error categories—not audio, prompts, responses, transcripts, or inserted text. |

## Expected interaction

```text
Fn held
  → model ready / Loading model
  → Listening
Fn released
  → Processing
  → local transcription
  → text injection
  → Done
  → Idle
```

If microphone permission, Accessibility permission, model installation, transcription, or injection fails, VoiceFlow shows an actionable error and returns the pipeline to a safe state.

## Requirements

VoiceFlow currently targets **macOS 14.0 or later** and is built with the native SwiftUI/AppKit stack. Development requires the full Xcode installation, not only Command Line Tools. The project uses Swift Package Manager through the Xcode project and depends on [Argmax OSS Swift](https://github.com/argmaxinc/argmax-oss-swift) for WhisperKit.

A real dictation session requires microphone permission and Accessibility or Input Monitoring permission as requested by macOS. Text injection into another application cannot be verified from a build-only test; it must be tested manually with a permitted target application.


## Getting started

Clone the repository and open the Xcode project:

```bash
git clone git@github.com:dha-aa/voiceflow.git
cd voiceflow
open voiceflow.xcodeproj
```

Select the `voiceflow` scheme and run the app from Xcode. VoiceFlow appears as a menu-bar application rather than a normal Dock application. Grant microphone access in **System Settings → Privacy & Security → Microphone**. Grant Accessibility or Input Monitoring access in **System Settings → Privacy & Security** when the app requests it or when text injection is blocked.

Open the menu-bar popover and go to **Settings → Models**. Select an installed model, download one, or use **Import Model** to choose a local WhisperKit Core ML model folder such as `Oriserve_Whisper-Hindi2Hinglish-Prime_889MB` from Finder. VoiceFlow validates the imported folder, verifies it can load through WhisperKit, and copies it into the managed model directory before showing it as installed. VoiceFlow stores its canonical model root under:

```text
~/Library/Application Support/dha-aa.voiceflow/models
```

WhisperKit’s downloaded repository layout is nested below that root under `models/argmaxinc/whisperkit-coreml/openai_whisper-<variant>`. Registered custom models use their own repository namespace and exact folder name, for example `models/nitinh/whisperkit-hinglish-coreml/Oriserve_Whisper-Hindi2Hinglish-Prime_889MB`. VoiceFlow validates the exact model folder and confirms that WhisperKit can load the required model components before marking a model as installed.

## Repository layout

| Path | Responsibility |
|---|---|
| `voiceflow/App/` | Application lifecycle and dependency composition. |
| `voiceflow/Core/Audio/` | Fn monitoring, microphone capture, and recording coordination. |
| `voiceflow/Core/Transcription/` | Model metadata, local model lifecycle, text processing, and WhisperKit session reuse. |
| `voiceflow/Core/Injection/` | Focused-app capture, Accessibility insertion, keyboard-event fallback, and completion feedback. |
| `voiceflow/Core/State/` | Explicit application states and state transitions. |
| `voiceflow/Core/Logging/` | Privacy-safe structured logging. |
| `voiceflow/UI/MenuBar/` | Menu-bar item, template icon behavior, and popover presentation. |
| `voiceflow/UI/Overlay/` | Recording HUD, state mapping, animation, and waveform display. |
| `voiceflow/UI/Settings/` | General, AI, Models, About, download coordination, and Settings window behavior. |
| `voiceflowTests/` | Unit, integration, model lifecycle, injection, overlay, and settings regression tests. |
| `specs/` | Product and implementation specifications for the completed work. |
| `scripts/release.sh` | Shared local release script for signed or unsigned DMGs. |
| `.github/workflows/release.yml` | Tag-triggered and manually triggered CI distribution workflow. |
| `docs/testing.md` | Automated and manual verification procedures. |
| `docs/release.md` | Release modes, artifact handling, credentials, and Gatekeeper guidance. |

## Privacy and security model

VoiceFlow’s normal recording-to-injection path is local. Network access is used for model catalog and model downloads, not for sending captured audio for remote transcription. An explicit, user-enabled Claude command is the only exception for dictated text: when enabled and the transcript begins with `Claude`, only the command remainder is sent to Anthropic. Do not add telemetry, remote transcription, or transcript-bearing diagnostics without a separate privacy review.

Logs must remain metadata-only. Safe examples include model IDs, model paths, audio file identifiers, file sizes, durations, state names, process identifiers, and error categories. Do not log microphone samples, audio contents, raw transcripts, inserted text, clipboard contents, or secret environment variables.

The app is intentionally non-sandboxed because the current implementation uses global Fn monitoring and cross-process Accessibility text injection. The Release target enables Hardened Runtime and carries only the microphone entitlement required by the app’s current design.

### AI settings and optional Claude commands

Open **Settings → AI** to choose the default AI provider. Claude is currently the only implemented provider; ChatGPT is shown as a future provider and does not make OpenAI requests in this version. Enable Claude commands, enter an Anthropic API key, and save it. VoiceFlow stores the key in the macOS Keychain, not in UserDefaults, source files, logs, or model files. The Claude model is selected per provider and can be entered manually or fetched from Anthropic with **Fetch available models**. The initial fallback is `claude-sonnet-5`; use a model ID available to your Anthropic account. Anthropic documents the model-list operation and direct Messages API request headers.[4] [5]

When enabled, a spoken transcript beginning with `Claude` routes only the remaining text to Claude. For example, `Claude, rewrite this politely` sends `rewrite this politely`; normal dictation does not call the network. Claude’s returned text is then sent through the existing injection path. Microphone audio and the ordinary local transcription remain local, but the explicitly routed text is intentionally sent to Anthropic using the user’s own key. VoiceFlow logs only provider/model identifiers, character counts, durations, and error categories—not API keys, prompts, responses, audio, or injected text.

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

The current suite contains **114 tests** covering the recording stage, pipeline coordination, model management, transcription session behavior, text injection, overlay state, AI provider/model persistence, Claude model-list decoding, and related regressions. See [`docs/testing.md`](docs/testing.md) for the full verification matrix.

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

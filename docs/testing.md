# VoiceFlow Testing Guide

VoiceFlow combines global keyboard monitoring, microphone capture, local WhisperKit model loading, text processing, Accessibility injection, SwiftUI/AppKit UI, and macOS distribution behavior. No single automated test can prove the entire system on every Mac, so verification is divided into deterministic XCTest coverage, local build checks, and manual end-to-end checks.

> Never use private speech, sensitive clipboard contents, or real personal data in tests. Test output and diagnostics must not contain audio, transcripts, or inserted text.

## Test environment

Testing requires a Mac with macOS 14 or later and the full Xcode installation. The project uses Swift Package Manager and the `voiceflow` Xcode scheme. If Command Line Tools are selected instead of Xcode, set:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

The current automated baseline is **102 XCTest tests with zero failures**. Tests that require microphone, Accessibility, a live WhisperKit model, or another application are supplemented by manual verification rather than being made dependent on a particular user machine.

## Automated XCTest suite

Run the full suite from the repository root:

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

A successful run ends with output similar to:

```text
Executed 102 tests, with 0 failures
** TEST SUCCEEDED **
```

Use a fresh derived-data path when diagnosing a build or dependency-resolution issue. The test command disables code signing because XCTest verification is not a distribution-signing check.

## Continuous integration quality gate

The `.github/workflows/ci.yml` workflow runs on every pull request targeting `main`, every push to `main`, and manual workflow runs. Its required job is named **CI Quality Gate**. The job validates project metadata, checks the release script and workflow YAML, validates property lists, checks for prohibited signing material, builds the Debug app without signing, and runs the complete XCTest suite.

GitHub reports each step in the pull request’s **Checks** section. The workflow also writes a job summary and uploads the XCTest result bundle when one is produced. A failed quality check, build, or test step causes the **CI Quality Gate** job to fail. The protected `main` branch requires this check, so GitHub prevents the normal pull-request merge path until the failure is resolved.

To reproduce the CI build and test stages locally, run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild \
  -project voiceflow.xcodeproj \
  -scheme voiceflow \
  -configuration Debug \
  -derivedDataPath /tmp/voiceflow-ci-debug \
  -destination 'platform=macOS' \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild \
  -project voiceflow.xcodeproj \
  -scheme voiceflow \
  -configuration Debug \
  -derivedDataPath /tmp/voiceflow-ci-tests \
  -destination 'platform=macOS' \
  ONLY_ACTIVE_ARCH=YES \
  -only-testing:voiceflowTests \
  test \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO
```

### Test coverage map

| Area | Representative coverage |
|---|---|
| Fn monitoring | Key-down, key-up, hold threshold, duplicate-event protection, and monitor lifecycle behavior. |
| Audio recording | Permission handling, start/stop behavior, no-audio handling, recorder failures, and deterministic test doubles. |
| Recording pipeline | Fn hold/release state changes, recorded-file creation, mono 16 kHz WAV-compatible output, model-readiness gating, and transition into processing. |
| Application state | Valid and invalid state transitions, completion timing, and safe error recovery. |
| WhisperKit integration | Package import and session-factory behavior using test doubles; model loading, caching, selection changes, missing models, and transcription error mapping. |
| Model management | Catalog entries, canonical local paths, direct Hub layout, component validation, nested-folder rejection, download progress, failed-load cleanup, persisted selection, and active-model deletion protection. |
| Text processing | Conservative whitespace and formatting behavior without changing dictated meaning. |
| Text injection | Empty input, missing target, Accessibility failure, keyboard fallback behavior, and injector error mapping. |
| Injection coordination | Processing/injecting/completed transitions, successful completion sound selection, disabled sound behavior, and no sound on failures. |
| Overlay UI | Loading model, Listening, Processing, Done, error states, animation cancellation, and approximately 400 ms completion dismissal. |
| Settings UI | General, Models, and About navigation; overlay visibility; completion sound defaults and persistence; model selection; download progress across tabs; and model actions. |
| Menu-bar UI | State-dependent icon selection and native template rendering behavior. |

Test doubles are used for system services so the deterministic suite does not require a physical microphone, a live Accessibility grant, or a downloaded WhisperKit model. This makes failures attributable to VoiceFlow logic rather than the local machine’s permissions or network state.

## Focused test commands

While iterating, select a test class or method with `-only-testing`:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild \
  -project voiceflow.xcodeproj \
  -scheme voiceflow \
  -configuration Debug \
  -derivedDataPath /tmp/voiceflow-focused-tests \
  -destination 'platform=macOS' \
  -only-testing:voiceflowTests/ModelManagerTests \
  test \
  CODE_SIGNING_ALLOWED=NO
```

Useful focused groups include `AudioRecorderTests`, `RecordingCoordinatorTests`, `RecordingPipelineIntegrationTests`, `TranscriptionEngineTests`, `ModelManagerTests`, `TextInjectorTests`, `InjectionCoordinatorTests`, `RecordingOverlayViewTests`, and `SettingsTests`. Run the complete suite before merging.

## Static and build checks

Run the release script syntax check and validate the workflow/document files before committing:

```bash
bash -n scripts/release.sh
ruby -e "require 'yaml'; YAML.load_file('.github/workflows/release.yml'); puts 'workflow YAML valid'"
git diff --check
plutil -lint voiceflow/Resources/Info.plist voiceflow/Resources/voiceflow.entitlements
```

Build an unsigned Release app without Apple credentials:

```bash
OUTPUT_DIR=/tmp/voiceflow-unsigned/dist \
DERIVED_DATA_DIR=/tmp/voiceflow-unsigned/derived-data \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
./scripts/release.sh --unsigned 1.0.0
```

The unsigned script path builds the app, creates a DMG, verifies that the DMG is structurally valid and mountable, checks for `VoiceFlow.app` and the Applications shortcut, and writes `SHA256SUMS.txt`. It deliberately does not claim code signing, notarization, stapling, or Gatekeeper acceptance.

## Manual end-to-end testing

Manual testing is required whenever a change affects the microphone, Fn handling, model loading, Accessibility, focused-app behavior, overlay timing, menu-bar state, Settings, or the distribution artifact. Use a disposable text field and non-sensitive phrases such as “The quick brown fox jumps over the lazy dog.”

### Permissions setup

Before testing, open **System Settings → Privacy & Security** and confirm microphone access for the build being tested. Confirm Accessibility or Input Monitoring permission for text injection. If permission is missing, VoiceFlow should show an actionable error rather than silently losing the result.

Use the same build throughout a manual session. A new Xcode build can have a different application identity or path and may require a separate permission grant.

### Core pipeline

| Scenario | Procedure | Expected result |
|---|---|---|
| Basic push-to-talk | Focus TextEdit, hold Fn, speak a short sentence, and release Fn. | Overlay shows Listening, then Processing, text is inserted into TextEdit, Done appears briefly, and the app returns to idle. |
| Brief Fn tap | Tap and release Fn without holding long enough to cross the hold threshold. | No recording session begins and no text is inserted. |
| Short utterance | Focus Notes or TextEdit, hold Fn, say “Hello,” and release. | A short transcription is injected without a no-audio error. |
| Long utterance | Focus a suitable editor, speak a paragraph for up to the supported recording duration, and release. | The full result is inserted or a graceful duration limit/error is shown without a crash. |
| Silence | Hold Fn for approximately three seconds without speaking. | The overlay shows a no-audio error and the pipeline returns to idle without inserting text. |
| Rapid sessions | Complete several short Fn sessions with less than one second between them. | Each session is isolated; there are no duplicate recordings, stale overlays, or state corruption. |

Do not evaluate transcription quality from an automated mock. For real quality verification, ensure the selected model is installed and loaded in Settings → Models before speaking.

### Model lifecycle

| Scenario | Procedure | Expected result |
|---|---|---|
| Existing model discovery | Launch the app with a previously downloaded model present. | The model appears installed and the persisted selection is restored. |
| Preload | Launch the app and wait for model readiness before holding Fn. | The selected model loads in the background and is reused for transcription. |
| Model switch | Select another installed model, wait for the readiness state, then dictate. | The prior session is invalidated, the new model is loaded, and the next transcription uses the new selection. |
| Download | Settings → Models → Download a model and observe progress. | Progress, Cancel, and folder navigation remain available; progress survives tab changes. The model is installed only after structural validation and real WhisperKit load validation succeed. |
| Failed download/load | Interrupt or invalidate a test artifact. | The artifact is not marked installed and failed model files are cleaned up safely. |
| Active-model deletion | Attempt to delete the selected active model. | Deletion is blocked until a replacement is selected or the active model is changed safely. |

The canonical model root is:

```text
~/Library/Application Support/dha-aa.voiceflow/models
```

VoiceFlow expects the direct WhisperKit Hub repository layout below that root and validates the exact final folder used by both detection and loading. Do not use a legacy `models--.../snapshots` path as a success criterion.

### Injection and permission recovery

| Scenario | Procedure | Expected result |
|---|---|---|
| Accessibility permitted | Focus an editable TextEdit field and complete dictation. | Text is inserted at the focused caret or selected range and the clipboard is not unexpectedly destroyed. |
| Accessibility denied | Revoke permission, complete a session, and observe the result. | VoiceFlow reports an injection failure and provides permission guidance; text is not silently reported as inserted. |
| Target changes | Focus an application, hold Fn, switch or close the target before release, and complete the session. | The failure is handled without a crash and the app returns to a safe state. |
| Read-only target | Focus a non-editable field and complete a session. | Injection failure is reported clearly; no false success state is shown. |
| Terminal target | Test in Terminal or another terminal emulator when relevant to the change. | Record whether keyboard-event injection works for that target and document any limitation. |

### Overlay, menu-bar, and Settings checks

Verify that the overlay remains a single compact rounded pill without an extra gray backing, dark shadow layer, clipping artifact, or misaligned border. Confirm the sequence **Listening → Processing → Done → idle** and that Done lasts briefly after successful injection.

Switch macOS between Light and Dark Mode and confirm that the idle menu-bar identity icon remains visible through native template rendering. Recording and error states should retain their semantic colors. Open Settings repeatedly and switch among General, Models, and About to confirm the window size and navigation remain stable.

In General, confirm that completion sound is off by default, can be enabled, persists after relaunch, and offers Tink, Pop, and Glass. Verify that a sound plays only after successful text injection and never after transcription or injection failure.

## Distribution-artifact testing

For an unsigned local DMG, verify the artifact and install it on a test Mac or test user account:

```bash
hdiutil verify /path/to/VoiceFlow-1.0.0.dmg
hdiutil attach -nobrowse -readonly /path/to/VoiceFlow-1.0.0.dmg
```

Confirm that the mounted image contains `VoiceFlow.app` and an `Applications` shortcut. Copy the app to Applications, launch it, grant permissions, and repeat the core pipeline and model-management checks. Eject the image after testing:

```bash
hdiutil detach /Volumes/VoiceFlow\ 1.0.0
```

An unsigned app may trigger Gatekeeper. Control-click the app and choose **Open**, then confirm. If macOS still blocks it, use **System Settings → Privacy & Security → Open Anyway**. This is expected for unsigned private distribution and is not evidence that the DMG is corrupt.

For a signed distribution, additionally verify the signature, notarization ticket, stapling, and Gatekeeper assessment as described in [`docs/release.md`](release.md). Do not claim those checks passed unless they were run against the actual final artifact.

## Failure-reporting checklist

When reporting a failure, include the macOS version, Xcode version, VoiceFlow commit, selected model identifier, target application, permission state, operation stage, and the relevant error category. Do not include audio, transcription text, inserted text, clipboard contents, private paths that reveal sensitive information, or secret values.

# Contributing to VoiceFlow

Thank you for contributing to VoiceFlow. VoiceFlow is a native macOS push-to-talk dictation application, so changes must preserve reliable keyboard handling, local transcription, safe text injection, clear user feedback, and privacy-safe diagnostics.

## Before you begin

Read [`README.md`](README.md) for the project overview, [`docs/testing.md`](docs/testing.md) for verification procedures, and [`docs/release.md`](docs/release.md) for distribution behavior. Review the relevant specification in [`specs/`](specs/) before changing an area of the product.

Development requires a Mac running macOS 14 or later with the full Xcode installation. The project is an Xcode project using Swift Package Manager. Command Line Tools alone are not enough to build the app or run its macOS test target.

## Development setup

Clone the repository and open the project:

```bash
git clone git@github.com:dha-aa/voiceflow.git
cd voiceflow
open voiceflow.xcodeproj
```

Use the `voiceflow` scheme. When invoking Xcode tools from a shell, select the full toolchain explicitly if Command Line Tools are active:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

The normal app flow requires microphone permission and Accessibility or Input Monitoring permission. Grant these permissions only to the local build you intend to test. Do not use a real dictated transcript, private clipboard data, or sensitive recordings in an issue, pull request, test fixture, or log.

## Branches and commits

Create a topic branch from the latest `main` branch:

```bash
git checkout main
git pull origin main
git checkout -b fix/short-description
```

Keep each commit focused on one coherent change. Use an imperative subject line that explains the outcome, such as `Fix model readiness gating before recording`. Include a body when the reason for the change, privacy impact, migration behavior, or verification limits are not obvious from the subject.

Do not commit generated artifacts or local machine state. The repository ignores common Xcode outputs and release artifacts, but always inspect `git status` before committing. In particular, do not commit DMGs, model files, audio files, certificates, private keys, provisioning profiles, `.xcuserstate` files, or Apple credentials.

## Architecture guidelines

VoiceFlow uses explicit state ownership. New behavior should preserve the central state progression rather than introducing hidden flags that can diverge from the overlay or menu-bar status:

```text
idle → preparingModel → recording → processing → injecting → completed → idle
```

Failures should become a typed `AppError`, produce a clear user-facing state, and return the app to a recoverable idle state. Cancellation and repeated Fn events must be idempotent. A failed operation must never be reported as successfully injected.

Keep the dependency direction understandable. Audio components should capture and finalize recordings; the recording coordinator should connect Fn events to recording; the transcription coordinator should call the local engine and text processor; the injection coordinator should perform insertion and completion feedback; UI controllers should observe state and present it rather than duplicating pipeline decisions.

Use protocols and test doubles where a component interacts with system services such as microphone capture, WhisperKit, Accessibility, keyboard events, sound playback, Launch Services, or Finder. Avoid changing production interfaces unless a genuine defect requires it and the change is documented in the pull request.

## Privacy requirements

VoiceFlow must keep audio and dictated content local during normal operation. Do not add remote transcription, analytics, cloud storage, or network requests to the recording-to-injection path without a separate design and privacy review.

Logging must remain metadata-only. It is acceptable to log model IDs, paths, byte counts, durations, state names, process identifiers, bundle identifiers, and categorized errors. It is not acceptable to log audio samples, audio file contents, raw transcription results, inserted text, clipboard contents, microphone data, or secret environment variables.

When adding a test, use deterministic strings such as `Test message` or synthetic audio fixtures. Do not record real speech into the repository or include personally identifying content in test output.

## Code style and implementation practices

Follow the existing Swift style and keep changes small enough to review. Prefer clear names, explicit ownership, structured concurrency, and `os.Logger`-based diagnostics over ad hoc `print` statements. Keep UI work on the main actor where required by SwiftUI/AppKit and avoid blocking the main actor with model loading or transcription.

When editing model management, preserve the canonical local model root and exact-folder validation behavior. A model should not appear installed until its required WhisperKit components are structurally valid and the same folder can be loaded by the transcription engine.

When editing injection, preserve permission checks, focused-application capture, clipboard safety, and the rule that success is reported only after insertion completes. Test Accessibility failure paths explicitly.

When editing the overlay or menu-bar UI, preserve the state-to-visual mapping and verify both Light and Dark Mode behavior. The menu-bar identity icon is a template asset; avoid hard-coded idle colors that break native appearance adaptation.

## Testing expectations

Before opening a pull request, run the complete XCTest suite:

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

The expected baseline is **102 tests with zero failures**, subject to intentional changes that are explained in the pull request. Run focused tests while iterating, but run the full suite before requesting review. See [`docs/testing.md`](docs/testing.md) for test groups and manual TextEdit verification.

If your change affects permissions, model downloads, text injection, Settings, the overlay, menu-bar status, or real microphone behavior, perform the corresponding manual check as well. Record only the outcome and metadata in the pull request; never attach audio or transcripts.

## Pull requests

A pull request should explain the user-visible or reliability impact, identify the files or components changed, describe privacy implications, and list the automated and manual checks performed. If a check could not be run, state why rather than implying success.

Use this summary format when helpful:

| Area | Details |
|---|---|
| Change | What behavior was changed and why? |
| Privacy impact | Does the change touch audio, text, clipboard, logs, or network access? |
| Automated tests | Command and result, including the test count. |
| Manual verification | Target app, permissions, model, and observed result. |
| Known limitations | Any environment, signing, notarization, or hardware limitation. |

Keep pull requests reviewable. Update documentation and tests when behavior or commands change. Do not include unrelated Xcode user-state changes in the pull request.

## Release contributions

Do not create a public production release from an unreviewed branch. Unsigned DMGs may be built for development or private sharing, but they can trigger Gatekeeper warnings. Signed and notarized releases require Apple credentials and must follow [`docs/release.md`](docs/release.md). Never add credentials to the repository or workflow source.

## Reporting security issues

Do not open a public issue containing private audio, transcripts, credentials, certificate material, or exploitable details. Contact the project maintainer privately with a minimal reproduction and enough metadata to understand the issue without disclosing dictated content.

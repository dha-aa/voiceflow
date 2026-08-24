# SPEC 07 — Production Readiness, CI, and Distribution

## Status and dependency

Specification 07 is the final stage in the current seven-part engineering sequence. It consumes the verified pipeline, overlay, Settings, and model-management behavior from Specifications 01–06 and defines hardening, validation, contributor CI, branch protection, and distribution. It must not silently introduce a new product feature.

The current repository supports two distribution classes:

1. **Unsigned distribution:** a normal mountable DMG can be created and published to GitHub Releases without Apple signing or notarization credentials.
2. **Signed production distribution:** an optional Developer ID and notarized DMG path is available when the required Apple credentials are supplied securely to the local environment or GitHub Actions.

Unsigned publication is a supported workflow, not a failed signed release. It must be clearly labeled because macOS Gatekeeper may warn users when they open an unsigned/unnotarized app. [1] [2]

## 1. Production goals

Production readiness means that VoiceFlow:

- Preserves local-only audio, model, and ordinary dictated-text handling while clearly disclosing the optional user-authorized Claude route.
- Has deterministic state/error behavior across permission, model, recording, transcription, and injection failures.
- Reuses a preloaded WhisperKit session without blocking the UI unnecessarily.
- Presents a focus-safe overlay and adaptive menu-bar identity icon.
- Provides clear Settings and model lifecycle behavior.
- Has reproducible local and hosted build/test checks.
- Blocks protected-main merges when the required CI quality gate fails.
- Produces a verified unsigned DMG without Apple secrets, and optionally a signed/notarized DMG with Apple credentials.

The goal is not to claim that an unsigned artifact has the trust properties of a notarized application. The release mode, artifact label, and installation guidance must remain explicit.

## 2. Current production baseline

| Area | Current implementation |
|---|---|
| Platform | macOS 14.0 minimum |
| Product | `VoiceFlow.app`, bundle ID `dha-aa.voiceflow` |
| Xcode target/scheme | Project `voiceflow.xcodeproj`, scheme `voiceflow` |
| Swift mode | Swift 5 language mode in the Xcode project |
| CI runner | `macos-15` with Xcode 16.4 selected by `maxim-lobanov/setup-xcode@v1` |
| App sandbox | Disabled; required by current global Fn and cross-process Accessibility behavior |
| Hardened Runtime | Enabled for Release configuration |
| Entitlements | Non-sandboxed app plus `com.apple.security.device.audio-input = true` |
| App identity | `LSUIElement = true`, no Dock icon, menu-bar agent |
| Local inference | WhisperKit 0.18.0, model files under app-owned Application Support storage |
| Tests | 129 XCTest methods in the current test target after provider-neutral request and screen-context forwarding coverage |
| Privacy | No audio, spoken text, transcript, prompt, response, or injected content in logs; optional Claude requests are explicit and text-only |
| Protected branch | `main` requires pull requests, approval, and the `CI Quality Gate` status check |

The actual project metadata, entitlements, and resolved dependencies are authoritative over this table. [3] [4] [5]

## 3. Edge-case contract

### Recording and Fn

The monitor uses a 250 ms sustained hold threshold. A short tap generates no recording callbacks. Duplicate down events and Fn-down while the state is not `.idle` are ignored. If the user releases Fn while microphone permission or model readiness is pending, startup is cancelled normally and no false audio completion is emitted. [6] [7]

The current implementation does **not** implement a maximum recording-duration cutoff, debounced 200 ms re-press policy, or a dedicated “microphone level stayed at zero” classifier. Do not document those as implemented. A missing recording URL is mapped to `.noAudioDetected`; silence or whitespace-only transcription is classified by the transcription stage. If a future maximum-duration or silence policy is required, it must be specified and tested as a separate change.

### Model lifecycle

A model is installed only when the canonical direct Hub directory passes structural preflight and, when the production validator is wired, real WhisperKit load validation. Legacy snapshot paths are not accepted. Failed downloads and failed load validation must not remain installed. Selection accepts only a valid installed model, and a changed selection cancels stale work and preloads the new session. [8] [9]

If a model disappears between preload and transcription, the engine resolves the folder again and reports `.modelNotInstalled` rather than attempting an implicit download. Heavy-memory-pressure retry logic is not currently implemented; a load failure maps to `.modelFailedToLoad` and returns the app to safe error recovery.

### First-launch onboarding and permissions

`OnboardingWindowController` presents `OnboardingView` on the first launch when `hasCompletedOnboarding` is not set. The welcome screen explains the hold Fn → speak → release workflow before any onboarding permission request. Microphone and Accessibility are presented one at a time with an explanation of why each permission is needed, the feature it enables, and a clear **Grant Permission** action.

The onboarding flow handles permissions independently. A denial does not terminate VoiceFlow or mark the permission as granted. The user can check again, continue without that capability, or skip setup. The completion screen explains which features remain unavailable and directs the user to **Settings → General → Permissions**. Completing or skipping setup persists `hasCompletedOnboarding` so the onboarding does not appear on every launch.

Screen Recording is currently informational only. VoiceFlow does not request it because screen-context AI is not implemented in this version; the onboarding and General Settings UI must say so explicitly rather than presenting a misleading system prompt.

`SystemVoiceFlowPermissionManager` is the single system-permission adapter. Microphone status/request uses AVFoundation authorization, Accessibility status/request uses ApplicationServices trust APIs, and the recovery UI can open the corresponding macOS Privacy & Security pane. Onboarding and Settings use this adapter rather than duplicating permission checks.

### Transcription

The transcription coordinator accepts work only while the shared state is `.processing`. Missing files, missing models, load failures, empty output, and runtime failures map to the documented shared errors. `TextProcessor` removes only known `[BLANK_AUDIO]`/`(inaudible)` artifacts and normalizes whitespace; it does not paraphrase or rewrite. The Claude processor checks the configured AI prefix before any Grammar Fix request. When Claude commands are enabled, Claude is selected, and the processed transcript begins with the persisted custom prefix, only the remaining text is sent to Anthropic over HTTPS; the returned text replaces the local transcript before injection. Matching is case-insensitive and rejects an embedded prefix inside another word. If no AI prefix matches and Grammar Fix is enabled, the complete ordinary transcript is sent to Claude with a correction-only system prompt. If both routes are disabled, normal dictation remains local.

### Injection

Empty text, missing target applications, invalid process identifiers, and missing Accessibility trust are rejected. Accessibility trust is requested before cross-process injection. When trusted, AX focused-element replacement is attempted first, followed by keyboard-event fallback if AX update fails. There is no clipboard fallback in the current implementation. A target application closing or changing state can produce an injection error; the injector must not guess another target. [10]

### Completion

Successful injection transitions through `.completed` and then `.idle` after approximately 400 ms. The completion sound is disabled by default and plays one selected native effect—Tink, Pop, or Glass—only after successful injection. Failed transcription, missing permission, empty text, and failed injection never play the sound. [11]

### Overlay and Settings

The overlay is a non-activating 270×58 pt panel with a 252×48 pt single black capsule, no native panel shadow, and no outer backing/border artifact. `.preparingModel` displays Loading model; `.recording` displays Listening; ordinary `.processing` and `.injecting` display Processing; an explicit AI request displays `Using Claude...` or the corresponding provider title before the response completes; `.completed` displays Done for about 400 ms; errors display a short message. Settings navigation uses explicit buttons, model download progress survives tab changes, active-model deletion is blocked, and the Settings window resets to its intended size when reopened. The Settings window contains General, AI, Models, and About panes. The AI pane persists the selected provider, per-provider model IDs, custom command prefix, and Grammar Fix setting; stores Claude credentials only in Keychain; shows a masked Configured state with Change/Remove controls; and lets the user refresh Claude’s model list through the authenticated provider API. The provider-neutral AI request contract carries processing mode, selected model, compact prompt mode, and optional screen context. ChatGPT is represented as future UI only and has no active request path. [12] [13] [14] [15]

## 4. Privacy and security requirements

All microphone capture, temporary recordings, model files, and default WhisperKit inference remain local. The application must not send audio to a remote endpoint. Optional Claude processing is an explicit user-enabled exception: a matching AI prefix sends only the persisted-prefix remainder to Anthropic, while Grammar Fix sends the complete ordinary transcript only when enabled and no AI prefix matches. The UI/documentation must disclose both text-only network boundaries.

Structured logs may contain only metadata needed for diagnosis, such as state names, model identifiers, canonical paths, process IDs, bundle identifiers, durations, byte counts, frame counts, progress, result character counts, and error categories. They must not contain audio samples, spoken phrases, raw transcription, Claude prompts, Claude responses, injected text, API keys, or full clipboard contents. [16]

Temporary audio files are created in the system temporary directory and are released by the recorder after stopping. Test fixtures must use synthetic or controlled data and must clean up generated files. Signing certificates, private keys, provisioning profiles, App Store Connect keys, and personal tokens must not be committed or printed.

The app is intentionally non-sandboxed in the current design. This is an architectural constraint for global Fn monitoring and cross-process Accessibility interaction, not a claim of App Store compatibility. Any App Store distribution effort would require a separate sandbox/injection design review.

## 5. Error presentation requirements

`AppError` currently has these cases:

```swift
.microphoneUnavailable
.noAudioDetected
.modelNotInstalled
.modelFailedToLoad
    .transcriptionFailed
    .claudeNotConfigured
    .claudeRequestFailed
    .injectionFailed
    .accessibilityPermissionDenied
```

The overlay maps them to current short messages: `Microphone unavailable`, `No audio detected`, `Model not installed`, `Model not loaded`, `Transcription failed`, `Configure Claude API key`, `Claude request failed`, `Insertion failed`, and `Allow Accessibility access`. The state manager recovers error states to `.idle` after about two seconds. [15] [16]

The current implementation still contains a small number of legacy `print` statements in state/coordinator paths. This is a known cleanup inconsistency. A hardening pass may replace them with `VoiceFlowLog` calls, but it must preserve privacy-safe metadata and must not change state sequencing. A future error-message redesign must update both `AppError` presentation tests and the overlay tests together.

## 6. Performance and memory verification

Performance should be measured on representative target hardware rather than treated as an unverified promise. Record at least:

| Metric | Verification expectation |
|---|---|
| Launch to status item | Measure from process launch to visible status item |
| Fn hold to Listening | Include hold threshold, permission already granted, and model-ready path |
| Fn release to Processing | Confirm state transition and callback scheduling |
| Model preload | Measure selected-model load and readiness from logs |
| Transcription | Measure controlled fixture duration by model variant |
| Injection | Measure from injection request to successful target update |
| Completion | Confirm Done lasts approximately 400 ms |
| Model download | Measure progress and final validation/load duration |

No performance target from the historical specification is considered passed solely because it was written down. The CI workflow validates build/test correctness, not real microphone latency, real model timing, or human-perceived UI quality.

Use Instruments for a separate manual memory audit. Pay special attention to `Task` ownership, recorder taps/files, model-selection cancellation, coordinator closures, and the cached WhisperKit session. Tests must prove that stale preload/download/completion tasks cannot overwrite newer state.

## 7. Automated CI quality gate

The contributor workflow is `.github/workflows/ci.yml`, named **CI Quality Gate**. It runs on:

- Pull requests targeting `main`.
- Pushes to `main`.
- Manual `workflow_dispatch` runs.

The workflow uses minimum `contents: read` permission, cancels obsolete runs for the same change, runs on `macos-15`, selects Xcode 16.4, and has a 45-minute timeout. [17]

The job performs these checks:

1. Checks out the repository.
2. Prints the selected Xcode version.
3. Validates release-relevant project metadata with `xcodebuild -showBuildSettings`.
4. Runs `bash -n scripts/release.sh`.
5. Parses both workflow YAML files with Ruby.
6. Lints the plist and entitlements with `plutil`.
7. Runs `git diff --check`.
8. Fails if signing/provisioning material appears in the repository.
9. Builds an unsigned Debug app with signing disabled.
10. Runs the complete `voiceflowTests` XCTest suite with signing disabled.
11. Uploads the `.xcresult` bundle when available.
12. Writes a job summary identifying `CI Quality Gate` as the required check.

The project does not currently use SwiftLint, SwiftFormat, or another dedicated lint/format tool. Repository/YAML/shell/plist checks are the current quality checks. Adding a formatter or linter is a separate change and must add a deterministic CI step plus a local reproduction command.

The local reproduction command is:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project voiceflow.xcodeproj \
  -scheme voiceflow \
  -configuration Debug \
  -derivedDataPath /tmp/voiceflow-tests \
  -destination 'platform=macOS' \
  ONLY_ACTIVE_ARCH=YES \
  -only-testing:voiceflowTests \
  test CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

## 8. Protected-main merge policy

GitHub branch protection for `main` requires a pull request, at least one approval, and the **CI Quality Gate** status check. Contributors must use:

```text
create branch → make changes → push branch → open/update PR → CI Quality Gate → review → merge
```

A failed or incomplete required check blocks the normal merge path. Direct repository-policy bypasses are administrative actions and are not part of the contributor workflow. Changes to the workflow job name must be accompanied by an update to the branch-protection required check; otherwise protected merges can become incorrectly configured.

## 9. Release workflow

The reusable local script is `scripts/release.sh`:

```bash
./scripts/release.sh --check
./scripts/release.sh --unsigned 1.0.0
./scripts/release.sh 1.0.0
```

`--check` validates the signed Release prerequisites without building or submitting. `--unsigned` builds Release with signing disabled, creates a UDZO DMG containing `VoiceFlow.app` and an Applications shortcut, verifies the DMG structure, and writes `dist/SHA256SUMS.txt`. It skips signature verification, notarization, stapling, and Gatekeeper assessment. The unsigned path requires no Apple credentials.

The default version path requires a Developer ID identity and either a notarization keychain profile or App Store Connect API-key credentials. It builds with Release Hardened Runtime settings, verifies the application signature, creates the DMG, submits it with `xcrun notarytool`, staples and validates the ticket with `xcrun stapler`, mounts the final DMG, verifies the signed app and Gatekeeper assessment, and only then generates the checksum. [18]

The GitHub workflow `.github/workflows/release.yml` runs on pushed `v*` tags and manual dispatch. Manual inputs are `unsigned`, `checks`, or `production-release` plus an optional semantic version. The current behavior is:

| Mode/event | Build | DMG | GitHub Release | Apple credentials |
|---|---|---|---|---|
| Tag `v1.0.0` | Unsigned | Yes | Yes, unsigned-labeled artifact | Not required |
| Manual `unsigned` | Unsigned | Yes | Yes, unsigned-labeled artifact | Not required |
| Manual `checks` | Unsigned Release app only | No | No | Not required |
| Manual `production-release` | Signed/notarized | Yes | Yes | Required |

The workflow runs XCTest before release work. It uploads DMG/checksum artifacts and creates a GitHub Release for unsigned or production modes. The release command uses explicit signed/unsigned branches and must remain safe under `set -euo pipefail`.

## 10. Unsigned DMG installation guidance

An unsigned/unnotarized DMG can be distributed, but macOS may show an unidentified-developer or verification warning. The release page and documentation must label it as unsigned. A user can generally install it by dragging VoiceFlow to Applications, then Control-clicking `VoiceFlow.app`, selecting **Open**, and confirming. If macOS retains the block, the user can review **System Settings → Privacy & Security → Open Anyway**. Users should install software only from a trusted release source and verify the published checksum before opening it.

This guidance does not bypass macOS security silently and does not claim that the app has notarization or Developer ID trust.

## 11. Tests and final verification

The current repository contains 129 XCTest methods distributed across state, audio, transcription, injection, overlay, Settings, LLM, onboarding, package-import, and baseline tests. The complete test target is the primary regression gate. [22]

Final verification must include:

- All automated XCTest tests pass locally and in CI.
- Debug build and Release unsigned build succeed with signing disabled.
- Project metadata, plist/entitlements, workflow YAML, shell syntax, and credential hygiene checks pass.
- Real hardware verifies first-launch onboarding, microphone and Accessibility permission prompts, skip/denial recovery, Settings permission controls, Fn hold threshold, model readiness, overlay focus safety, Accessibility injection, Settings persistence, model download validation, completion sound behavior, and Light/Dark menu-bar icon rendering.
- The core TextEdit pipeline is repeated after any UI or Settings change.
- The unsigned DMG mounts and passes `hdiutil verify`; its contents include `VoiceFlow.app` and an Applications shortcut.
- Signed distribution, stapling, and Gatekeeper assessment are verified only when real Apple credentials are available.

## 12. Acceptance criteria

- The application builds with the documented target, bundle ID, entitlements, and Release settings.
- All automated tests pass with zero failures.
- CI runs on PRs to `main` and reports a single required `CI Quality Gate` check.
- Branch protection requires the CI check and pull-request approval before normal merging.
- No dedicated lint/format tool is claimed unless one is actually configured; current repository quality checks remain documented.
- Privacy-safe logging contains no audio, speech, transcript, Claude prompt, Claude response, API key, or injected text.
- First-launch onboarding explains the workflow and each current permission before requesting it, allows skip/denial recovery, and exposes unresolved permission recovery in General Settings. Screen Recording is explicitly not requested until screen-context AI exists.
- Optional Claude processing is disabled by default, uses a Keychain-stored user key, shows only a masked Configured state after saving, sends only the remainder after the persisted custom prefix, uses the configured Claude model, and returns failures to a recoverable state. Grammar Fix is independently opt-in, uses a correction-only system prompt, sends the complete ordinary transcript only when no AI prefix matches, and never runs before AI-prefix detection.
- AI settings persist the selected provider, per-provider model, custom prefix, and Grammar Fix preference. Claude model refresh uses the authenticated Models API; ChatGPT remains explicitly unimplemented and makes no request.
- Provider implementations use the shared AI request and prompt-mode contract. Optional screen context is passed only through an explicit future context provider; the current app captures no screen content.
- Known edge cases are mapped to safe errors or explicitly recorded as current limitations.
- Model download → structural validation → exact-folder load validation → detection → preload → transcription remains consistent.
- Completion sound remains success-only and disabled by default.
- Overlay remains focus-safe, compact, single-surface, and state-synchronized.
- Unsigned release mode creates a mountable DMG and checksum without Apple secrets.
- Unsigned tags/manual releases publish the DMG and checksum to GitHub Releases and clearly label the artifact.
- Signed mode remains optional and fails early with actionable missing-credential errors when selected without credentials.
- No signing secrets or local diagnostic probes are committed.

## 13. Completion gate

VoiceFlow is production-ready for the chosen distribution class only when:

1. The full XCTest and CI quality gates pass.
2. Protected-main merge requirements are active and verified.
3. Manual real-hardware checks pass for microphone, Fn, model readiness, overlay, Accessibility, Settings, and completion feedback.
4. The selected distribution mode is explicitly identified as unsigned or signed/notarized.
5. An unsigned DMG is mountable and checksum-verified, or a signed DMG additionally passes signature, stapling, notarization, and Gatekeeper checks.
6. Any remaining limitations—such as non-sandboxed architecture, absent maximum-duration cutoff, no clipboard fallback, and remaining legacy `print` diagnostics—are disclosed rather than hidden.

## 14. Handoff

After this gate, future work should be specified as a new change rather than silently modifying the seven-stage sequence. The stable architecture is:

```text
FnKeyMonitor
    ↓
AudioRecorder ── audioLevel ──→ OverlayWindowController / WaveformView
    ↓
RecordingCoordinator ── model readiness + target app capture
    ↓
TranscriptionEngine ── canonical model resolution + cached WhisperKit session
    ↓
TextProcessor
    ↓
TranscriptionCoordinator ── optional Claude command ──→ Anthropic Messages API
    ↓
TextInjector ── AX first, keyboard fallback when trusted
    ↓
InjectionCoordinator ── success-only sound + completed timing
    ↓
AppStateManager ──→ OverlayWindowController
                  └─→ MenuBarController / MenuBarPopoverView

ModelManager ──→ TranscriptionEngine
             └─→ Settings / ModelDownloadCoordinator
```

## References

[1]: ../scripts/release.sh "VoiceFlow reusable release script"
[2]: ../docs/release.md "VoiceFlow release and Gatekeeper guidance"
[3]: ../voiceflow.xcodeproj/project.pbxproj "VoiceFlow Xcode target and build settings"
[4]: ../voiceflow/Resources/Info.plist "VoiceFlow bundle metadata"
[5]: ../voiceflow/Resources/voiceflow.entitlements "VoiceFlow entitlements"
[6]: ../voiceflow/Core/Audio/FnKeyMonitor.swift "Fn hold monitor"
[7]: ../voiceflow/Core/Audio/RecordingCoordinator.swift "Recording readiness and cancellation"
[8]: ../voiceflow/Core/Transcription/ModelManager.swift "Canonical model management"
[9]: ../voiceflow/Core/Transcription/TranscriptionEngine.swift "WhisperKit session lifecycle"
[10]: ../voiceflow/Core/Injection/TextInjector.swift "Accessibility-safe text injection"
[11]: ../voiceflow/Core/Injection/InjectionCoordinator.swift "Completion state and sound"
[12]: ../voiceflow/UI/Overlay/OverlayWindowController.swift "Overlay window behavior"
[13]: ../voiceflow/UI/Settings/SettingsView.swift "Settings navigation"
[14]: ../voiceflow/UI/Settings/AISettingsView.swift "AI settings UI"
[15]: ../voiceflow/Core/LLM/AIModelCatalog.swift "Claude model discovery"
[16]: ../voiceflow/Core/Logging/VoiceFlowLogger.swift "Privacy-safe logging"
[17]: ../voiceflow/UI/Settings/SettingsWindowController.swift "Settings window lifecycle"
[18]: ../voiceflow/Core/State/AppState.swift "Shared error cases"
[19]: ../voiceflow/UI/Overlay/RecordingOverlayView.swift "Overlay error messages"
[20]: ../.github/workflows/ci.yml "Contributor CI quality gate"
[21]: ../.github/workflows/release.yml "Release workflow"
[22]: ../voiceflowTests "VoiceFlow XCTest target"
[23]: https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution "Apple notarization guidance"
[24]: ../voiceflow/Core/LLM/ClaudeClient.swift "Claude BYOK client and command processor"
[25]: https://platform.claude.com/docs/en/manage-claude/authentication "Anthropic Claude API authentication"
[26]: https://platform.claude.com/docs/en/api/models/list "Anthropic List Models API"

## Implementation inconsistency register

The historical specification described only signed/notarized distribution and required removing all `print` calls, a maximum recording duration, retry-on-memory-pressure behavior, clipboard fallback injection, and broad VoiceOver requirements. The current implementation does not provide all of those features. This document records them as limitations or future hardening work rather than misrepresenting them as complete.

The historical specification also used a placeholder bundle identifier and an old snapshot-cache model path. The current source of truth is `dha-aa.voiceflow` and the direct Hub layout under the app-owned model root. The current repository additionally supports a credential-free unsigned DMG release and a protected-main CI quality gate.

## Completion gate

Specification 07 is complete when the automated CI/build/test checks and the selected distribution-mode verification pass, all known current limitations are documented, and no release or security claim exceeds what the actual artifact and available credentials prove.

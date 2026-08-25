# Change 032: Settings Dependency Injection

## Date
2026-08-25

## Status
Implemented and verified

## Reason
Settings still created two services outside the application composition boundary: `ModelDownloadCoordinator` was constructed by `SettingsWindowController`, and `GeneralSettingsView` could default-construct both its permission manager and audio-retention manager. That allowed Settings to diverge from the runtime’s shared service instances and made ownership harder for future agents to trace.

## Scope
This change affects the Settings dependency graph and application composition only. User-facing Settings behavior, model download behavior, permission behavior, and audio-retention behavior remain unchanged.

## Implementation
`ApplicationComposition` now owns the shared `ModelDownloadCoordinator` and `SystemVoiceFlowPermissionManager` instances.

`MenuBarController`, `MenuBarPopoverView`, `SettingsWindowController`, and `SettingsView` forward those same instances explicitly. `SettingsWindowController` no longer constructs or replaces a download coordinator when Settings opens or reopens.

`GeneralSettingsView` now requires `VoiceFlowPermissionManaging` and `AudioRetentionManager` explicitly and no longer creates fallback production services. Existing tests provide explicit fixtures or production implementations as appropriate.

Updated `docs/architecture.md` and `specs/spec_06_settings_and_model_management.md` to describe the ownership boundary and the five current Settings destinations accurately.

## Behavior and compatibility
The Settings window remains a singleton with fixed geometry. Model download progress continues to survive navigation because the coordinator remains long-lived and is now owned by the composition root. Permission status and audio retention continue to use the same production implementations; only construction ownership changed.

## Tests and verification
Updated the Settings construction tests for the explicit permission dependency. The clean `./scripts/buildapp.sh --clean` build passed and produced `build/VoiceFlow.app`. The full `voiceflowTests` XCTest suite passed with 186 tests and 0 failures. `git diff --check` passed before the build.

## Documentation updated

- `docs/architecture.md`
- `specs/spec_06_settings_and_model_management.md`
- `spec_changes/032_settings_dependency_injection.md`

## Feature flags
Not applicable. No feature flag or rollout behavior changed.

## Migration
Not applicable. No persisted data, configuration, model, file, Keychain, or interface migration changed.

## Known limitations or follow-up
`OnboardingView` still permits an optional permission-manager default because it is a separate first-launch flow. It is not part of the Settings dependency graph and was intentionally left unchanged in this focused refactor.

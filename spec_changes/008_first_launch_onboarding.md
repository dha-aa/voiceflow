# Specification Change 008 — First-Launch Onboarding and Permission Recovery

## Summary

VoiceFlow now presents a first-launch onboarding window before the user begins using the menu-bar dictation workflow. The flow explains what the app does, explains each current permission before requesting it, supports skip/denial recovery, and ends with a setup-complete quick test.

## Onboarding flow

`OnboardingWindowController` shows `OnboardingView` when the UserDefaults key `hasCompletedOnboarding` is not set. The application pipeline remains initialized normally, but onboarding is brought to the front so permission requests are initiated from the guided flow rather than appearing without context.

The screens are:

1. **Welcome.** Explain hold Fn → speak → release Fn, local transcription, and focused-field injection.
2. **Microphone.** Explain that microphone access is needed to listen and transcribe speech, then provide **Grant Permission**.
3. **Accessibility.** Explain that Accessibility access is needed to insert generated text into the current application, then provide **Grant Permission**.
4. **Screen Recording information.** Explain that screen context would be an optional future AI capability. Do not request this permission because screen-context AI is not implemented in the current version.
5. **Setup Complete.** Show “Everything is ready. Try saying something.” and explain the quick Fn test.

Already-granted required permissions are skipped automatically. Microphone and Accessibility are presented one at a time. Accessibility may require the user to approve VoiceFlow in macOS Privacy & Security and then choose **Check Again**.

## Denial and skip behavior

A denied permission never becomes marked as granted. The user may retry, continue without the permission, or skip setup. The app remains usable where possible:

| Permission | Impact when unavailable |
|---|---|
| Microphone | Voice recording and transcription cannot start. |
| Accessibility | VoiceFlow may transcribe, but cannot insert text into another application. |
| Screen Recording | No current feature is affected because screen-context AI is not implemented. |

Completing or skipping onboarding persists `hasCompletedOnboarding`. The completion screen lists unresolved required permissions and points to **Settings → General → Permissions**.

## Shared permission adapter

`SystemVoiceFlowPermissionManager` in `voiceflow/Core/Permissions/VoiceFlowPermissions.swift` is shared by onboarding and General Settings. It provides status, request, and system-settings navigation for microphone and Accessibility. It reports Screen Recording as `notRequired` rather than displaying a misleading grant action.

General Settings displays current Microphone and Accessibility status, a **Grant Permission** action, and an **Open System Settings** action for unresolved permissions. Status is refreshed when the app becomes active again after the user visits System Settings.

## Privacy and lifecycle

The onboarding UI does not send audio, transcripts, screenshots, or credentials. It does not alter the existing local transcription default or the explicit Claude command network boundary. Closing onboarding without choosing skip leaves the app usable and allows onboarding to appear again on the next launch.

## Tests and manual verification

Deterministic tests cover the initial welcome state, permission ordering, granted-permission progression, denial and skip behavior, completion persistence, and the fact that Screen Recording is explained but never requested. Manual verification must use a fresh test-user profile or the onboarding preference must be reset safely; do not reset unrelated application preferences.

## References

- [VoiceFlowPermissions.swift](../voiceflow/Core/Permissions/VoiceFlowPermissions.swift)
- [OnboardingView.swift](../voiceflow/UI/Onboarding/OnboardingView.swift)
- [OnboardingWindowController.swift](../voiceflow/UI/Onboarding/OnboardingWindowController.swift)
- [GeneralSettingsView.swift](../voiceflow/UI/Settings/GeneralSettingsView.swift)

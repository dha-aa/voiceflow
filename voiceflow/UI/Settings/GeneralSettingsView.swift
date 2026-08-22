//
//  GeneralSettingsView.swift
//  VoiceFlow
//

import ServiceManagement
import SwiftUI

enum VoiceFlowSettingsDefaults {
    static let showRecordingOverlayKey = "showRecordingOverlay"
    static let playCompletionSoundKey = "playCompletionSound"
    static let completionSoundEffectKey = "completionSoundEffect"

    static func showRecordingOverlay(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: showRecordingOverlayKey) as? Bool ?? true
    }

    static func playCompletionSound(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: playCompletionSoundKey) as? Bool ?? false
    }

    static func completionSoundEffect(in defaults: UserDefaults = .standard) -> CompletionSoundEffect {
        let rawValue = defaults.string(forKey: completionSoundEffectKey) ?? ""
        return CompletionSoundEffect(rawValue: rawValue) ?? .tink
    }
}

struct GeneralSettingsView: View {
    @AppStorage(VoiceFlowSettingsDefaults.showRecordingOverlayKey) private var showRecordingOverlay = true
    @AppStorage(VoiceFlowSettingsDefaults.playCompletionSoundKey) private var playCompletionSound = false
    @AppStorage(VoiceFlowSettingsDefaults.completionSoundEffectKey) private var completionSoundEffect = CompletionSoundEffect.tink.rawValue
    @State private var launchAtLoginError: String?

    var body: some View {
        Form {
            Section("Push-to-Talk") {
                LabeledContent("Hold Fn to Talk") {
                    Label("Enabled", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                Text("Hold Fn to record. Release Fn to transcribe.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Startup") {
                Toggle(
                    "Launch VoiceFlow at Login",
                    isOn: Binding(
                        get: { isLaunchAtLoginEnabled },
                        set: { setLaunchAtLogin($0) }
                    )
                )
                Text(launchAtLoginStatusDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Feedback") {
                Toggle("Play completion sound", isOn: $playCompletionSound)
                Picker("Sound effect", selection: $completionSoundEffect) {
                    ForEach(CompletionSoundEffect.allCases) { effect in
                        Text(effect.rawValue).tag(effect.rawValue)
                    }
                }
                .disabled(!playCompletionSound)

                Text("Play a short sound after text is successfully injected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Appearance") {
                Toggle("Show recording overlay when recording", isOn: $showRecordingOverlay)
                Text("The overlay shows listening, processing, completion, and error states without taking focus.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(24)
        .navigationTitle("General")
    }

    private var isLaunchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    private var launchAtLoginStatusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled:
            "VoiceFlow will start automatically when you log in."
        case .requiresApproval:
            "Approval is required in System Settings → Login Items."
        case .notRegistered:
            "VoiceFlow will not start automatically."
        case .notFound:
            "Launch-at-login is unavailable for this app installation."
        @unknown default:
            "Launch-at-login status is unavailable."
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = "Could not update Login Items: \(error.localizedDescription)"
        }
    }
}

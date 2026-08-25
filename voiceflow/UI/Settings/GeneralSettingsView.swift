//
//  GeneralSettingsView.swift
//  VoiceFlow
//

import AppKit
import ServiceManagement
import SwiftUI

enum VoiceFlowSettingsDefaults {
    static let showRecordingOverlayKey = "showRecordingOverlay"
    static let playCompletionSoundKey = "playCompletionSound"
    static let completionSoundEffectKey = "completionSoundEffect"
    static let audioRetentionPolicyKey = "audioRetentionPolicy"

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

    static func audioRetentionPolicy(in defaults: UserDefaults = .standard) -> AudioRetentionPolicy {
        let rawValue = defaults.string(forKey: audioRetentionPolicyKey) ?? ""
        return AudioRetentionPolicy(rawValue: rawValue) ?? .never
    }
}

@MainActor
struct GeneralSettingsView: View {
    @AppStorage(VoiceFlowSettingsDefaults.showRecordingOverlayKey) private var showRecordingOverlay = true
    @AppStorage(VoiceFlowSettingsDefaults.playCompletionSoundKey) private var playCompletionSound = false
    @AppStorage(VoiceFlowSettingsDefaults.completionSoundEffectKey) private var completionSoundEffect = CompletionSoundEffect.tink.rawValue
    @AppStorage(VoiceFlowSettingsDefaults.audioRetentionPolicyKey) private var audioRetentionPolicy = AudioRetentionPolicy.never.rawValue
    @State private var launchAtLoginError: String?
    @State private var showingDeleteAllAudioConfirmation = false
    @State private var permissionStatuses: [VoiceFlowPermission: VoiceFlowPermissionStatus] = [:]
    @State private var requestingPermission: VoiceFlowPermission?
    private let permissionManager: VoiceFlowPermissionManaging
    private let audioRetentionManager: AudioRetentionManager

    init(
        permissionManager: VoiceFlowPermissionManaging? = nil,
        audioRetentionManager: AudioRetentionManager? = nil
    ) {
        self.permissionManager = permissionManager ?? SystemVoiceFlowPermissionManager()
        self.audioRetentionManager = audioRetentionManager ?? AudioRetentionManager()
    }

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

            Section("Audio") {
                Picker("Keep recorded audio", selection: $audioRetentionPolicy) {
                    ForEach(AudioRetentionPolicy.allCases) { policy in
                        Text(policy.rawValue).tag(policy.rawValue)
                    }
                }
                .onChange(of: audioRetentionPolicy) { _, rawValue in
                    if let policy = AudioRetentionPolicy(rawValue: rawValue) {
                        audioRetentionManager.setPolicy(policy)
                    }
                }

                Button("Delete All Audio", role: .destructive) {
                    showingDeleteAllAudioConfirmation = true
                }

                Text("Recordings are stored locally in the VoiceFlow audio folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .alert("Delete All Audio?", isPresented: $showingDeleteAllAudioConfirmation) {
                Button("Delete All Audio", role: .destructive) {
                    audioRetentionManager.deleteAllAudio()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This permanently removes all stored VoiceFlow recordings.")
            }

            Section("Appearance") {
                Toggle("Show recording overlay when recording", isOn: $showRecordingOverlay)
                Text("The overlay shows listening, processing, completion, and error states without taking focus.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Permissions") {
                permissionRow(.microphone)
                permissionRow(.accessibility)
                Text("Screen Recording is not required in this version because screen-context AI is not available yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .padding(24)
        .navigationTitle("General")
        .onAppear {
            refreshPermissionStatuses()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissionStatuses()
        }

    }

    @ViewBuilder
    private func permissionRow(_ permission: VoiceFlowPermission) -> some View {
        let status = permissionStatuses[permission] ?? .notGranted
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Label(permission.title, systemImage: permission.systemImage)
                Spacer()
                Label(status.title, systemImage: status.isGranted ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundStyle(status.isGranted ? .green : .secondary)
                    .font(.callout)
            }
            Text(permission.featureDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
            if !status.isGranted {
                HStack {
                    Button(requestingPermission == permission ? "Requesting…" : "Grant Permission") {
                        Task { await requestPermission(permission) }
                    }
                    .disabled(requestingPermission != nil)

                    Button("Open System Settings") {
                        permissionManager.openSystemSettings(for: permission)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private func refreshPermissionStatuses() {
        for permission in VoiceFlowPermission.allCases {
            permissionStatuses[permission] = permissionManager.status(for: permission)
        }
    }

    private func requestPermission(_ permission: VoiceFlowPermission) async {
        guard requestingPermission == nil else { return }
        requestingPermission = permission
        _ = await permissionManager.request(permission)
        requestingPermission = nil
        refreshPermissionStatuses()
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

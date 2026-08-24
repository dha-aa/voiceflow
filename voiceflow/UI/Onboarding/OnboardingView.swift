//
//  OnboardingView.swift
//  VoiceFlow
//
//  First-launch welcome and permission setup experience.
//

import Observation
import SwiftUI

@MainActor
@Observable
final class OnboardingModel {
    enum Step: Equatable {
        case welcome
        case permission(VoiceFlowPermission)
        case complete
    }

    private(set) var step: Step = .welcome
    private(set) var permissionStatuses: [VoiceFlowPermission: VoiceFlowPermissionStatus] = [:]
    private(set) var isRequestingPermission = false
    private(set) var lastRequestFailed = false

    let permissionManager: VoiceFlowPermissionManaging
    let userDefaults: UserDefaults
    let onFinished: () -> Void

    init(
        permissionManager: VoiceFlowPermissionManaging? = nil,
        userDefaults: UserDefaults = .standard,
        onFinished: @escaping () -> Void = {}
    ) {
        self.permissionManager = permissionManager ?? SystemVoiceFlowPermissionManager()
        self.userDefaults = userDefaults
        self.onFinished = onFinished
        refreshStatuses()
    }

    var currentPermission: VoiceFlowPermission? {
        guard case .permission(let permission) = step else { return nil }
        return permission
    }

    var currentPermissionStatus: VoiceFlowPermissionStatus {
        guard let currentPermission else { return .notGranted }
        return permissionStatuses[currentPermission] ?? permissionManager.status(for: currentPermission)
    }

    var requiredPermissionsMissing: [VoiceFlowPermission] {
        VoiceFlowPermission.allCases.filter {
            $0.isRequiredForCurrentVersion && permissionStatuses[$0] != .granted
        }
    }

    var isFirstLaunch: Bool {
        !userDefaults.bool(forKey: VoiceFlowOnboardingDefaults.completedKey)
    }

    func beginPermissions() {
        refreshStatuses()
        step = .permission(.microphone)
        advancePastGrantedPermissions()
    }

    func refreshStatuses() {
        for permission in VoiceFlowPermission.allCases {
            permissionStatuses[permission] = permissionManager.status(for: permission)
        }
    }

    func grantCurrentPermission() async {
        guard let permission = currentPermission,
              permission.isRequiredForCurrentVersion,
              !isRequestingPermission else { return }

        isRequestingPermission = true
        lastRequestFailed = false
        let granted = await permissionManager.request(permission)
        isRequestingPermission = false
        permissionStatuses[permission] = permissionManager.status(for: permission)

        if granted || permissionStatuses[permission] == .granted {
            advanceToNextPermission(after: permission)
        } else {
            lastRequestFailed = true
        }
    }

    func checkCurrentPermissionAgain() {
        refreshStatuses()
        lastRequestFailed = false
        guard let permission = currentPermission else { return }
        if permissionStatuses[permission] == .granted {
            advanceToNextPermission(after: permission)
        }
    }

    func skipCurrentPermission() {
        guard let permission = currentPermission else { return }
        advanceToNextPermission(after: permission)
    }

    func skipSetup() {
        userDefaults.set(true, forKey: VoiceFlowOnboardingDefaults.completedKey)
        onFinished()
    }

    func finish() {
        userDefaults.set(true, forKey: VoiceFlowOnboardingDefaults.completedKey)
        onFinished()
    }

    private func advancePastGrantedPermissions() {
        guard let permission = currentPermission,
              permissionStatuses[permission] == .granted else { return }
        advanceToNextPermission(after: permission)
    }

    private func advanceToNextPermission(after permission: VoiceFlowPermission) {
        lastRequestFailed = false
        guard let index = VoiceFlowPermission.allCases.firstIndex(of: permission) else {
            step = .complete
            return
        }

        let remaining = VoiceFlowPermission.allCases.dropFirst(index + 1)
        if let nextPermission = remaining.first(where: {
            $0 == .screenRecording || permissionStatuses[$0] != .granted
        }) {
            step = .permission(nextPermission)
        } else {
            step = .complete
        }
    }
}

@MainActor
struct OnboardingView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 28)
                .padding(.horizontal, 44)

            Divider()
                .padding(.top, 24)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 56)
                .padding(.vertical, 28)

            footer
                .padding(.horizontal, 44)
                .padding(.bottom, 24)
        }
        .frame(width: 600, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "waveform.and.mic")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 46, height: 46)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text("Welcome to VoiceFlow")
                    .font(.system(size: 21, weight: .semibold))
                Text("Fast, private voice input for macOS")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .welcome:
            welcomeContent
        case .permission(let permission):
            permissionContent(permission)
        case .complete:
            completeContent
        }
    }

    private var welcomeContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Speak naturally. VoiceFlow does the rest.")
                .font(.system(size: 25, weight: .semibold))

            Text("VoiceFlow turns your voice into text without interrupting the app you are using. Your audio is transcribed on this Mac, then the result is inserted into the focused text field.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 13) {
                workflowRow(symbol: "hand.tap", title: "Hold Fn", detail: "Start a voice recording.")
                workflowRow(symbol: "waveform", title: "Speak", detail: "VoiceFlow listens and transcribes locally.")
                workflowRow(symbol: "arrow.down.to.line", title: "Release Fn", detail: "The final text is inserted into your focused app.")
            }
            .padding(18)
            .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))

            Text("You will review the permissions VoiceFlow needs before any system prompt appears.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func permissionContent(_ permission: VoiceFlowPermission) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(spacing: 12) {
                Image(systemName: permission.systemImage)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.tint)
                    .frame(width: 42, height: 42)
                    .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text(permission.title)
                        .font(.title2.weight(.semibold))
                    Text(permission.isRequiredForCurrentVersion ? "Required for this feature" : "Optional future capability")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Text(permission.explanation)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            Text(permission.featureDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            statusView(for: permission)
        }
    }

    private var completeContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Setup Complete")
                .font(.system(size: 26, weight: .semibold))

            Text("Everything is ready. Try saying something.")
                .font(.title3)

            Text("Hold Fn while you speak, then release it. VoiceFlow will place the transcription in the app you were using.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !model.requiredPermissionsMissing.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Some features are unavailable until you grant:")
                        .font(.headline)
                    ForEach(model.requiredPermissionsMissing) { permission in
                        Label("\(permission.title): \(permission.featureDescription)", systemImage: "exclamationmark.circle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Text("You can grant these later from Settings → General → Permissions.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    @ViewBuilder
    private func statusView(for permission: VoiceFlowPermission) -> some View {
        switch model.currentPermissionStatus {
        case .granted:
            Label("Granted", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .notRequired:
            Label("Not required yet", systemImage: "info.circle")
                .foregroundStyle(.secondary)
        case .notGranted:
            if model.lastRequestFailed {
                Label("Not granted yet. You can continue and grant it later in Settings.", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            } else {
                Text("VoiceFlow will ask macOS for this permission after you choose Grant Permission.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Skip setup for now") {
                model.skipSetup()
            }
            .buttonStyle(.borderless)

            Spacer()

            switch model.step {
            case .welcome:
                Button("Review Permissions") {
                    model.beginPermissions()
                }
                .buttonStyle(.borderedProminent)
            case .permission(let permission):
                if permission == .screenRecording {
                    Button("Continue") {
                        model.skipCurrentPermission()
                    }
                    .buttonStyle(.borderedProminent)
                } else if model.currentPermissionStatus == .granted {
                    Button("Continue") {
                        model.checkCurrentPermissionAgain()
                    }
                    .buttonStyle(.borderedProminent)
                } else if model.lastRequestFailed {
                    HStack(spacing: 10) {
                        Button("Check Again") {
                            model.checkCurrentPermissionAgain()
                        }
                        Button("Continue without \(permission.title)") {
                            model.skipCurrentPermission()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    Button("Grant Permission") {
                        Task { await model.grantCurrentPermission() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isRequestingPermission)
                }
            case .complete:
                Button("Start Using VoiceFlow") {
                    model.finish()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func workflowRow(symbol: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

//
//  VoiceFlowPermissions.swift
//  VoiceFlow
//
//  Permission contracts shared by first-launch onboarding and Settings recovery.
//

import AVFoundation
import ApplicationServices
import AppKit
import Foundation

@MainActor
enum VoiceFlowPermission: String, CaseIterable, Identifiable, Hashable {
    case microphone
    case accessibility
    case screenRecording

    var id: String { rawValue }

    var title: String {
        switch self {
        case .microphone:
            "Microphone"
        case .accessibility:
            "Accessibility"
        case .screenRecording:
            "Screen Recording"
        }
    }

    var systemImage: String {
        switch self {
        case .microphone:
            "mic.fill"
        case .accessibility:
            "hand.raised.fill"
        case .screenRecording:
            "rectangle.inset.filled.and.person.filled"
        }
    }

    var explanation: String {
        switch self {
        case .microphone:
            "VoiceFlow needs microphone access to listen to your voice and transcribe what you say."
        case .accessibility:
            "VoiceFlow needs Accessibility access to insert generated text into the app you are currently using."
        case .screenRecording:
            "Screen Recording access would be used only for optional AI context from your screen. Screen context is not available in this version, so VoiceFlow will not request this permission yet."
        }
    }

    var featureDescription: String {
        switch self {
        case .microphone:
            "Without it, voice recording and transcription cannot start."
        case .accessibility:
            "Without it, VoiceFlow can transcribe but cannot insert text into another app."
        case .screenRecording:
            "This is reserved for a future screen-context feature and is not required for dictation."
        }
    }

    var isRequiredForCurrentVersion: Bool {
        self != .screenRecording
    }
}

enum VoiceFlowPermissionStatus: Equatable {
    case granted
    case notGranted
    case notRequired

    var title: String {
        switch self {
        case .granted:
            "Granted"
        case .notGranted:
            "Not granted"
        case .notRequired:
            "Not required yet"
        }
    }

    var isGranted: Bool {
        self == .granted
    }
}

@MainActor
protocol VoiceFlowPermissionManaging: AnyObject {
    func status(for permission: VoiceFlowPermission) -> VoiceFlowPermissionStatus
    func request(_ permission: VoiceFlowPermission) async -> Bool
    func openSystemSettings(for permission: VoiceFlowPermission)
}

@MainActor
final class SystemVoiceFlowPermissionManager: VoiceFlowPermissionManaging {
    func status(for permission: VoiceFlowPermission) -> VoiceFlowPermissionStatus {
        switch permission {
        case .microphone:
            AVCaptureDevice.authorizationStatus(for: .audio) == .authorized ? .granted : .notGranted
        case .accessibility:
            AXIsProcessTrusted() ? .granted : .notGranted
        case .screenRecording:
            .notRequired
        }
    }

    func request(_ permission: VoiceFlowPermission) async -> Bool {
        switch permission {
        case .microphone:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .accessibility:
            let options = [
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
            ] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            return AXIsProcessTrusted()
        case .screenRecording:
            return false
        }
    }

    func openSystemSettings(for permission: VoiceFlowPermission) {
        let urlString: String?
        switch permission {
        case .microphone:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .accessibility:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .screenRecording:
            urlString = nil
        }

        guard let urlString, let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}

enum VoiceFlowOnboardingDefaults {
    static let completedKey = "hasCompletedOnboarding"
}

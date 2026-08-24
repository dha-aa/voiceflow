//
//  RecordingOverlayView.swift
//  VoiceFlow
//

import Observation
import SwiftUI

@MainActor
@Observable
final class RecordingOverlayModel {
    enum PresentationState: Equatable {
        case hidden
        case preparingModel
        case listening
        case processing
        case done
        case error(AppError)
    }

    private(set) var presentationState: PresentationState = .hidden
    private(set) var audioLevel: Float = 0

    var isShowingDoneState: Bool {
        presentationState == .done
    }

    var isVisible: Bool {
        presentationState != .hidden
    }

    func updateAudioLevel(_ level: Float) {
        audioLevel = min(max(level, 0), 1)
    }

    func showPreparingModelState() {
        presentationState = .preparingModel
    }

    func showListeningState() {
        presentationState = .listening
    }

    func showProcessingState() {
        presentationState = .processing
    }

    func showDoneState() {
        presentationState = .done
    }

    func showErrorState(_ error: AppError) {
        presentationState = .error(error)
    }

    func resetDoneState() {
        if presentationState == .done {
            presentationState = .hidden
        }
    }

    func hide() {
        presentationState = .hidden
    }
}

struct RecordingOverlayView: View {
    let model: RecordingOverlayModel
    @State private var pulse = false

    var body: some View {
        Group {
            if model.isVisible {
                HStack(spacing: 9) {
                    indicator
                        .frame(width: 18)

                    if showsWaveform {
                        WaveformView(
                            audioLevel: model.audioLevel,
                            isDimmed: model.presentationState == .processing
                        )
                    } else {
                        Color.clear.frame(width: 0, height: 20)
                    }

                    Text(label)
                        .font(.system(size: 12.5, weight: .medium, design: .default))
                        .foregroundStyle(Color.white.opacity(0.94))
                        .lineLimit(1)
                        .frame(minWidth: 66, alignment: .leading)
                }
                    .padding(.horizontal, 12)
                    .frame(width: 252, height: 48)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.black.opacity(0.84))
                    )
                    // The capsule fill is intentionally the only visible
                    // overlay surface: no border, shadow, or backing layer.
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                .animation(.easeOut(duration: 0.18), value: model.presentationState)
                .onAppear {
                    pulse = true
                }
            }
        }
        .frame(width: 270, height: 58)
        .animation(.easeInOut(duration: 0.15), value: model.presentationState)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var showsWaveform: Bool {
        switch model.presentationState {
        case .preparingModel, .listening, .processing:
            true
        case .hidden, .done, .error:
            false
        }
    }

    @ViewBuilder
    private var indicator: some View {
        switch model.presentationState {
        case .preparingModel:
            ProgressView()
                .controlSize(.small)
                .tint(.white)
        case .listening:
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
                .scaleEffect(pulse ? 1.0 : 0.9)
                .animation(
                    .easeInOut(duration: 0.75).repeatForever(autoreverses: true),
                    value: pulse
                )
        case .processing:
            ProgressView()
                .controlSize(.small)
                .tint(.white)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 16, weight: .semibold))
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 16, weight: .semibold))
        case .hidden:
            EmptyView()
        }
    }

    private var label: String {
        switch model.presentationState {
        case .preparingModel: "Loading model..."
        case .listening: "Listening..."
        case .processing: "Processing..."
        case .done: "Done!"
        case .error(let error): error.message
        case .hidden: ""
        }
    }

    private var accessibilityLabel: String {
        switch model.presentationState {
        case .preparingModel: "Loading model"
        case .listening: "Listening"
        case .processing: "Processing"
        case .done: "Done"
        case .error(let error): error.message
        case .hidden: "VoiceFlow overlay hidden"
        }
    }
}

private extension AppError {
    var message: String {
        switch self {
        case .microphoneUnavailable: "Microphone unavailable"
        case .noAudioDetected: "No audio detected"
        case .modelNotInstalled: "Model not installed"
        case .modelFailedToLoad: "Model not loaded"
        case .transcriptionFailed: "Transcription failed"
        case .claudeNotConfigured: "Configure Claude API key"
        case .claudeRequestFailed: "Claude request failed"
        case .injectionFailed: "Insertion failed"
        case .accessibilityPermissionDenied: "Allow Accessibility access"
        }
    }
}

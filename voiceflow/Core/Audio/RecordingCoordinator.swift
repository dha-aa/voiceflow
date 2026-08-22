//
//  RecordingCoordinator.swift
//  VoiceFlow
//
//  Created by Dhananjay Singh on 22/08/26.
//

import AppKit
import OSLog

@MainActor
protocol ModelReadinessChecking: AnyObject {
    func waitUntilReady() async throws
}

final class RecordingCoordinator {
    private let stateManager: AppStateManager
    private let recorder: AudioRecording
    private let keyMonitor: FnKeyMonitor
    private weak var modelReadiness: ModelReadinessChecking?

    private var targetApplication: NSRunningApplication?
    private var recordingStartTask: Task<Void, Never>?
    private var isFnHeld = false

    // Callback for when recording is complete.
    var onRecordingComplete: ((URL, NSRunningApplication?) -> Void)?

    init(
        stateManager: AppStateManager,
        recorder: AudioRecorder,
        keyMonitor: FnKeyMonitor,
        modelReadiness: ModelReadinessChecking? = nil
    ) {
        self.stateManager = stateManager
        self.recorder = recorder
        self.keyMonitor = keyMonitor
        self.modelReadiness = modelReadiness
        setupKeyMonitorCallbacks()
    }

    init(
        stateManager: AppStateManager,
        recorder: AudioRecording,
        keyMonitor: FnKeyMonitor,
        modelReadiness: ModelReadinessChecking? = nil
    ) {
        self.stateManager = stateManager
        self.recorder = recorder
        self.keyMonitor = keyMonitor
        self.modelReadiness = modelReadiness
        setupKeyMonitorCallbacks()
    }

    func start() {
        keyMonitor.start()
    }

    func stop() {
        keyMonitor.stop()
        recordingStartTask?.cancel()
        recordingStartTask = nil
        isFnHeld = false

        if recorder.isRecording {
            _ = recorder.stopRecording()
        }
        targetApplication = nil
    }

    private func setupKeyMonitorCallbacks() {
        keyMonitor.onFnKeyDown = { [weak self] in
            self?.handleFnKeyDown()
        }

        keyMonitor.onFnKeyUp = { [weak self] in
            self?.handleFnKeyUp()
        }
    }

    private func handleFnKeyDown() {
        // The key monitor emits one down event per sustained hold. The extra
        // guard keeps this class safe if a monitor emits a duplicate event.
        guard !isFnHeld, stateManager.currentState == .idle else {
            print("Ignoring Fn key down - recording pipeline is already active")
            return
        }

        isFnHeld = true
        targetApplication = NSWorkspace.shared.frontmostApplication

        recordingStartTask?.cancel()
        recordingStartTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let permissionGranted = await recorder.requestPermission()
            guard !Task.isCancelled, isFnHeld, stateManager.currentState == .idle else {
                return
            }

            guard permissionGranted else {
                print("Microphone permission denied")
                stateManager.transition(to: .error(.microphoneUnavailable))
                targetApplication = nil
                return
            }

            if let modelReadiness {
                VoiceFlowLog.pipeline.info("model_readiness_wait_started")
                stateManager.transition(to: .preparingModel)
                do {
                    try await modelReadiness.waitUntilReady()
                    guard !Task.isCancelled, isFnHeld else {
                        stateManager.transition(to: .idle)
                        targetApplication = nil
                        return
                    }
                    VoiceFlowLog.pipeline.info("model_ready_before_recording")
                } catch is CancellationError {
                    stateManager.transition(to: .idle)
                    targetApplication = nil
                    return
                } catch {
                    VoiceFlowLog.pipeline.error("model_ready_before_recording_failed error=\(String(describing: error), privacy: .public)")
                    stateManager.transition(to: .error(.modelFailedToLoad))
                    targetApplication = nil
                    return
                }
            }

            guard stateManager.currentState == .preparingModel || stateManager.currentState == .idle else {
                targetApplication = nil
                return
            }

            do {
                try recorder.startRecording()
                guard isFnHeld else {
                    _ = recorder.stopRecording()
                    targetApplication = nil
                    return
                }
                stateManager.transition(to: .recording)
                VoiceFlowLog.pipeline.info("recording_ready_started")
                print("State → recording")
            } catch {
                print("Failed to start recording: \(error.localizedDescription)")
                stateManager.transition(to: .error(.microphoneUnavailable))
                targetApplication = nil
            }
        }
    }

    private func handleFnKeyUp() {
        guard isFnHeld else { return }
        isFnHeld = false
        recordingStartTask?.cancel()
        recordingStartTask = nil

        // Releasing before permission or engine startup completes is a normal
        // cancellation, not an error and not a recording completion.
        guard stateManager.currentState == .recording else {
            targetApplication = nil
            return
        }

        guard let audioURL = recorder.stopRecording() else {
            print("Failed to stop recording - no audio was captured")
            targetApplication = nil
            stateManager.transition(to: .error(.noAudioDetected))
            return
        }

        stateManager.transition(to: .processing)
        VoiceFlowLog.pipeline.info("recording_stage_completed audio_id=\(VoiceFlowLog.audioIdentifier(for: audioURL), privacy: .public)")
        print("State → processing")
        print("Recording complete: \(audioURL.path)")
        onRecordingComplete?(audioURL, targetApplication)
        targetApplication = nil
    }
}

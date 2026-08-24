//
//  TranscriptionCoordinator.swift
//  VoiceFlow
//

import AppKit
import Foundation
import OSLog

final class TranscriptionCoordinator {
    private let stateManager: AppStateManager
    private let engine: TranscriptionEngine
    private let processor: TextProcessor
    private let claudeProcessor: ClaudeCommandProcessor

    var onTranscriptionComplete: ((String, NSRunningApplication?) -> Void)?
    var onAIProcessingStarted: ((AIProvider) -> Void)?

    init(
        stateManager: AppStateManager,
        engine: TranscriptionEngine,
        processor: TextProcessor,
        claudeProcessor: ClaudeCommandProcessor = ClaudeCommandProcessor()
    ) {
        self.stateManager = stateManager
        self.engine = engine
        self.processor = processor
        self.claudeProcessor = claudeProcessor
        VoiceFlowLog.pipeline.debug("transcription_coordinator_initialized")
    }

    func transcribe(audioURL: URL, targetApp: NSRunningApplication?) async {
        let audioID = VoiceFlowLog.audioIdentifier(for: audioURL)
        guard stateManager.currentState == .processing else {
            VoiceFlowLog.pipeline.debug("transcription_request_ignored audio_id=\(audioID, privacy: .public) reason=state_not_processing current_state=\(String(describing: self.stateManager.currentState), privacy: .public)")
            return
        }

        let startedAt = Date()
        VoiceFlowLog.pipeline.info("transcription_pipeline_started audio_id=\(audioID, privacy: .public) target_application_present=\(targetApp != nil, privacy: .public)")

        do {
            let rawText = try await engine.transcribe(audioURL: audioURL)
            VoiceFlowLog.pipeline.debug("transcription_stage_succeeded audio_id=\(audioID, privacy: .public) raw_character_count=\(rawText.count, privacy: .public)")

            let processedText = processor.process(rawText)
            guard !processedText.isEmpty else {
                VoiceFlowLog.pipeline.error("transcription_processing_failed audio_id=\(audioID, privacy: .public) reason=empty_processed_text")
                throw TranscriptionEngine.TranscriptionEngineError.noAudioDetected
            }

            if let provider = claudeProcessor.requestedProvider(for: processedText) {
                onAIProcessingStarted?(provider)
            }
            let finalText = try await claudeProcessor.processIfRequested(processedText) ?? processedText
            guard !finalText.isEmpty else {
                VoiceFlowLog.pipeline.error("transcription_processing_failed audio_id=\(audioID, privacy: .public) reason=empty_final_text")
                throw TranscriptionEngine.TranscriptionEngineError.noAudioDetected
            }

            stateManager.transition(to: .injecting)
            VoiceFlowLog.pipeline.info("transcription_pipeline_ready_for_injection audio_id=\(audioID, privacy: .public) processed_character_count=\(finalText.count, privacy: .public) duration_seconds=\(Date().timeIntervalSince(startedAt), privacy: .public) target_application_present=\(targetApp != nil, privacy: .public)")
            guard let onTranscriptionComplete else {
                VoiceFlowLog.pipeline.error("transcription_injection_callback_missing audio_id=\(audioID, privacy: .public) reason=no_injection_handler")
                stateManager.transition(to: .error(.injectionFailed))
                return
            }
            onTranscriptionComplete(finalText, targetApp)
            VoiceFlowLog.pipeline.info("transcription_completion_callback_delivered audio_id=\(audioID, privacy: .public) target_application_present=\(targetApp != nil, privacy: .public)")
        } catch let error as ClaudeCommandError {
            let appError: AppError
            switch error {
            case .notConfigured, .keychainUnavailable:
                appError = .claudeNotConfigured
            case .requestFailed, .emptyResponse:
                appError = .claudeRequestFailed
            }
            VoiceFlowLog.pipeline.error("claude_pipeline_failed audio_id=\(audioID, privacy: .public) app_error=\(String(describing: appError), privacy: .public)")
            stateManager.transition(to: .error(appError))
        } catch let error as TranscriptionEngine.TranscriptionEngineError {
            transitionToError(for: error, audioID: audioID, startedAt: startedAt)
        } catch {
            VoiceFlowLog.pipeline.error("transcription_pipeline_failed audio_id=\(audioID, privacy: .public) duration_seconds=\(Date().timeIntervalSince(startedAt), privacy: .public) category=runtime error=\(String(describing: error), privacy: .public)")
            stateManager.transition(to: .error(.transcriptionFailed))
        }
    }

    private func transitionToError(
        for error: TranscriptionEngine.TranscriptionEngineError,
        audioID: String,
        startedAt: Date
    ) {
        let appError: AppError
        switch error {
        case .modelNotSelected, .modelNotInstalled:
            appError = .modelNotInstalled
        case .modelFailedToLoad:
            appError = .modelFailedToLoad
        case .noAudioDetected:
            appError = .noAudioDetected
        case .audioFileNotFound, .transcriptionFailed:
            appError = .transcriptionFailed
        }

        VoiceFlowLog.pipeline.error("transcription_pipeline_failed audio_id=\(audioID, privacy: .public) duration_seconds=\(Date().timeIntervalSince(startedAt), privacy: .public) category=\(error.category, privacy: .public) app_error=\(String(describing: appError), privacy: .public)")
        stateManager.transition(to: .error(appError))
    }
}

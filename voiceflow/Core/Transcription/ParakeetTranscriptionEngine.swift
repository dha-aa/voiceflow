//
//  ParakeetTranscriptionEngine.swift
//  VoiceFlow
//
//  Local Parakeet TDT 0.6B v3 transcription through FluidAudio/Core ML.
//

import FluidAudio
import Foundation
import OSLog

protocol ParakeetSession {
    func transcribe(audioURL: URL) async throws -> String
}

protocol ParakeetSessionFactory {
    func makeSession(modelFolder: URL) async throws -> ParakeetSession
}

private struct LiveParakeetSessionFactory: ParakeetSessionFactory {
    func makeSession(modelFolder: URL) async throws -> ParakeetSession {
        let models = try await AsrModels.load(
            from: modelFolder,
            version: .v3,
            encoderPrecision: .int8
        )
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        VoiceFlowLog.transcription.info(
            "parakeet_manager_loaded model_folder=\(modelFolder.path, privacy: .public)"
        )
        return LiveParakeetSession(manager: manager)
    }
}

private final class LiveParakeetSession: ParakeetSession {
    private let manager: AsrManager

    init(manager: AsrManager) {
        self.manager = manager
    }

    func transcribe(audioURL: URL) async throws -> String {
        var decoderState = try TdtDecoderState(decoderLayers: 2)
        let result = try await manager.transcribe(audioURL, decoderState: &decoderState)
        return result.text
    }
}

@MainActor
final class ParakeetTranscriptionEngine: SpeechTranscriptionEngine {
    private let modelManager: ParakeetModelProviding
    private let sessionFactory: ParakeetSessionFactory

    private var cachedSession: ParakeetSession?
    private var inFlightLoadTask: Task<ParakeetSession, Error>?
    private var preloadTask: Task<Void, Never>?

    init(modelManager: ParakeetModelManager) {
        self.modelManager = modelManager
        self.sessionFactory = LiveParakeetSessionFactory()
        VoiceFlowLog.transcription.debug("parakeet_transcription_engine_initialized")
    }

    init(
        modelManager: ParakeetModelProviding,
        sessionFactory: ParakeetSessionFactory
    ) {
        self.modelManager = modelManager
        self.sessionFactory = sessionFactory
        VoiceFlowLog.transcription.debug("parakeet_transcription_engine_initialized")
    }

    var displayName: String { "Parakeet TDT v3" }

    func prepare() async throws {
        try await waitUntilReady()
    }

    func waitUntilReady() async throws {
        _ = try await session()
    }

    func preloadSelectedModel() {
        preloadTask?.cancel()
        preloadTask = nil
        inFlightLoadTask?.cancel()
        inFlightLoadTask = nil
        cachedSession = nil

        guard modelManager.isInstalled else {
            VoiceFlowLog.transcription.debug("parakeet_model_preload_skipped reason=model_not_installed")
            return
        }

        VoiceFlowLog.transcription.info("parakeet_model_preload_requested")
        preloadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await self.session()
                VoiceFlowLog.transcription.info("parakeet_model_preload_succeeded")
            } catch is CancellationError {
                VoiceFlowLog.transcription.debug("parakeet_model_preload_cancelled")
            } catch {
                VoiceFlowLog.transcription.error("parakeet_model_preload_failed error=\(String(describing: error), privacy: .public)")
            }
            self.preloadTask = nil
        }
    }

    func modelSelectionDidChange() {
        preloadSelectedModel()
    }

    func transcribe(audioURL: URL) async throws -> String {
        let audioID = VoiceFlowLog.audioIdentifier(for: audioURL)
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw SpeechTranscriptionError.audioFileNotFound
        }
        guard modelManager.isSupportedPlatform else {
            throw SpeechTranscriptionError.modelFailedToLoad(
                underlying: ParakeetModelManager.ParakeetModelError.unsupportedPlatform
            )
        }

        let startedAt = Date()
        do {
            let session = try await session()
            let text = try await session.transcribe(audioURL: audioURL)
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty else {
                throw SpeechTranscriptionError.noAudioDetected
            }
            VoiceFlowLog.transcription.info(
                "parakeet_transcription_succeeded audio_id=\(audioID, privacy: .public) duration_seconds=\(Date().timeIntervalSince(startedAt), privacy: .public) result_character_count=\(trimmedText.count, privacy: .public)"
            )
            return text
        } catch let error as SpeechTranscriptionError {
            throw error
        } catch {
            VoiceFlowLog.transcription.error(
                "parakeet_transcription_failed audio_id=\(audioID, privacy: .public) duration_seconds=\(Date().timeIntervalSince(startedAt), privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
            throw SpeechTranscriptionError.transcriptionFailed(underlying: error)
        }
    }

    private func session() async throws -> ParakeetSession {
        guard modelManager.isSupportedPlatform else {
            throw SpeechTranscriptionError.modelFailedToLoad(
                underlying: ParakeetModelManager.ParakeetModelError.unsupportedPlatform
            )
        }
        guard modelManager.isInstalled else {
            throw SpeechTranscriptionError.modelNotInstalled
        }
        if let cachedSession {
            return cachedSession
        }
        if let inFlightLoadTask {
            do {
                return try await inFlightLoadTask.value
            } catch let error as SpeechTranscriptionError {
                throw error
            } catch {
                throw SpeechTranscriptionError.modelFailedToLoad(underlying: error)
            }
        }

        let modelDirectory = modelManager.modelDirectory
        VoiceFlowLog.transcription.info(
            "parakeet_model_load_started model_directory=\(modelDirectory.path, privacy: .public)"
        )
        let loadTask = Task { @MainActor [sessionFactory] in
            try await sessionFactory.makeSession(modelFolder: modelDirectory)
        }
        inFlightLoadTask = loadTask
        do {
            let newSession = try await loadTask.value
            if modelManager.isInstalled {
                cachedSession = newSession
            }
            inFlightLoadTask = nil
            VoiceFlowLog.transcription.info("parakeet_model_load_succeeded")
            return newSession
        } catch is CancellationError {
            inFlightLoadTask = nil
            throw CancellationError()
        } catch {
            inFlightLoadTask = nil
            VoiceFlowLog.transcription.error("parakeet_model_load_failed error=\(String(describing: error), privacy: .public)")
            throw SpeechTranscriptionError.modelFailedToLoad(underlying: error)
        }
    }
}

//
//  ParakeetTranscriptionEngine.swift
//  VoiceFlow
//
//  Local Parakeet TDT transcription through FluidAudio/Core ML.
//

import FluidAudio
import Foundation
import OSLog

protocol ParakeetSession {
    func transcribe(audioURL: URL) async throws -> String
}

protocol ParakeetSessionFactory {
    func makeSession(modelFolder: URL, variant: ParakeetModelVariant) async throws -> ParakeetSession
}

private struct LiveParakeetSessionFactory: ParakeetSessionFactory {
    func makeSession(modelFolder: URL, variant: ParakeetModelVariant) async throws -> ParakeetSession {
        let models = try await AsrModels.load(
            from: modelFolder,
            version: variant.asrVersion,
            encoderPrecision: variant.encoderPrecision
        )
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        VoiceFlowLog.transcription.info(
            "parakeet_manager_loaded variant=\(variant.rawValue, privacy: .public) model_folder=\(modelFolder.path, privacy: .public)"
        )
        return LiveParakeetSession(manager: manager, variant: variant)
    }
}

private final class LiveParakeetSession: ParakeetSession {
    private let manager: AsrManager
    private let variant: ParakeetModelVariant

    init(manager: AsrManager, variant: ParakeetModelVariant) {
        self.manager = manager
        self.variant = variant
    }

    func transcribe(audioURL: URL) async throws -> String {
        var decoderState = try TdtDecoderState(decoderLayers: variant.asrVersion.decoderLayers)
        let result = try await manager.transcribe(audioURL, decoderState: &decoderState)
        return result.text
    }
}

@MainActor
final class ParakeetTranscriptionEngine: SpeechTranscriptionEngine {
    private let modelManager: ParakeetModelProviding
    private let sessionFactory: ParakeetSessionFactory

    private var cachedSession: ParakeetSession?
    private var cachedVariant: ParakeetModelVariant?
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

    var displayName: String { modelManager.selectedVariant.displayName }

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
        cachedVariant = nil

        guard modelManager.isInstalled else {
            VoiceFlowLog.transcription.debug(
                "parakeet_model_preload_skipped reason=model_not_installed variant=\(self.modelManager.selectedVariant.rawValue, privacy: .public)"
            )
            return
        }

        VoiceFlowLog.transcription.info(
            "parakeet_model_preload_requested variant=\(self.modelManager.selectedVariant.rawValue, privacy: .public)"
        )
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
        let variant = modelManager.selectedVariant
        do {
            let loadedSession = try await session()
            let text = try await loadedSession.transcribe(audioURL: audioURL)
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty else {
                throw SpeechTranscriptionError.noAudioDetected
            }
            VoiceFlowLog.transcription.info(
                "parakeet_transcription_succeeded variant=\(variant.rawValue, privacy: .public) audio_id=\(audioID, privacy: .public) duration_seconds=\(Date().timeIntervalSince(startedAt), privacy: .public) result_character_count=\(trimmedText.count, privacy: .public)"
            )
            return text
        } catch let error as SpeechTranscriptionError {
            throw error
        } catch {
            VoiceFlowLog.transcription.error(
                "parakeet_transcription_failed variant=\(variant.rawValue, privacy: .public) audio_id=\(audioID, privacy: .public) duration_seconds=\(Date().timeIntervalSince(startedAt), privacy: .public) error=\(String(describing: error), privacy: .public)"
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

        let variant = modelManager.selectedVariant
        if let cachedSession, cachedVariant == variant {
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
            "parakeet_model_load_started variant=\(variant.rawValue, privacy: .public) model_directory=\(modelDirectory.path, privacy: .public)"
        )
        let loadTask = Task { @MainActor [sessionFactory, modelDirectory, variant] in
            try await sessionFactory.makeSession(modelFolder: modelDirectory, variant: variant)
        }
        inFlightLoadTask = loadTask
        do {
            let newSession = try await loadTask.value
            if modelManager.isInstalled, modelManager.selectedVariant == variant {
                cachedSession = newSession
                cachedVariant = variant
            }
            inFlightLoadTask = nil
            VoiceFlowLog.transcription.info(
                "parakeet_model_load_succeeded variant=\(variant.rawValue, privacy: .public)"
            )
            return newSession
        } catch is CancellationError {
            inFlightLoadTask = nil
            throw CancellationError()
        } catch {
            inFlightLoadTask = nil
            VoiceFlowLog.transcription.error(
                "parakeet_model_load_failed variant=\(variant.rawValue, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
            throw SpeechTranscriptionError.modelFailedToLoad(underlying: error)
        }
    }
}

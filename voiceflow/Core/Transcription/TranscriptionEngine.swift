//
//  TranscriptionEngine.swift
//  VoiceFlow
//
//  Local WhisperKit session lifecycle and audio transcription.
//

import Foundation
import OSLog
import WhisperKit

protocol WhisperKitSession {
    func transcribe(audioURL: URL) async throws -> String
}

protocol WhisperKitSessionFactory {
    func makeSession(modelID: String, modelFolder: URL, downloadBase: URL) async throws -> WhisperKitSession
}

private struct LiveWhisperKitSessionFactory: WhisperKitSessionFactory {
    func makeSession(modelID: String, modelFolder: URL, downloadBase: URL) async throws -> WhisperKitSession {
        let config = WhisperKitConfig(
            model: modelID,
            downloadBase: downloadBase,
            modelFolder: modelFolder.path,
            load: true,
            download: false
        )
        VoiceFlowLog.transcription.info(
            "whisperkit_configuration_created model_id=\(modelID, privacy: .public) whisperkit_model_folder=\(modelFolder.path, privacy: .public) download_base=\(downloadBase.path, privacy: .public)"
        )
        return LiveWhisperKitSession(pipe: try await WhisperKit(config))
    }
}

private final class LiveWhisperKitSession: WhisperKitSession {
    private let pipe: WhisperKit

    init(pipe: WhisperKit) {
        self.pipe = pipe
    }

    func transcribe(audioURL: URL) async throws -> String {
        let results = try await pipe.transcribe(audioPath: audioURL.path)
        return results.map(\.text).joined(separator: " ")
    }
}

@MainActor
final class TranscriptionEngine: WhisperKitModelLoadValidator, ModelReadinessChecking {
    private let modelManager: ModelManager
    private let sessionFactory: WhisperKitSessionFactory

    private var cachedSession: WhisperKitSession?
    private var cachedModelID: String?
    private var inFlightLoadTask: Task<WhisperKitSession, Error>?
    private var inFlightModelID: String?
    private var preloadTask: Task<Void, Never>?

    init(
        modelManager: ModelManager,
        sessionFactory: WhisperKitSessionFactory = LiveWhisperKitSessionFactory()
    ) {
        self.modelManager = modelManager
        self.sessionFactory = sessionFactory
        VoiceFlowLog.transcription.debug("transcription_engine_initialized")
    }

    func prepare() async throws {
        VoiceFlowLog.transcription.info("transcription_prepare_requested")
        try await waitUntilReady()
        VoiceFlowLog.transcription.info("transcription_prepare_succeeded")
    }

    func waitUntilReady() async throws {
        VoiceFlowLog.transcription.info("model_readiness_requested")
        _ = try await session()
        VoiceFlowLog.transcription.info("model_ready model_id=\(self.cachedModelID ?? "<none>", privacy: .public)")
    }

    /// Starts loading the persisted/selected model without making the caller wait.
    /// The task is owned by the engine so it can be cancelled when selection changes,
    /// and an eventual transcription request shares the same in-flight load.
    func preloadSelectedModel() {
        preloadTask?.cancel()
        preloadTask = nil
        inFlightLoadTask?.cancel()
        inFlightLoadTask = nil
        inFlightModelID = nil
        invalidateCachedSession()

        guard let selectedModelID = modelManager.selectedModelId,
              !selectedModelID.isEmpty else {
            VoiceFlowLog.transcription.debug("model_preload_skipped reason=model_not_selected")
            return
        }

        VoiceFlowLog.transcription.info("model_preload_requested model_id=\(selectedModelID, privacy: .public)")
        preloadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await self.session()
                VoiceFlowLog.transcription.info("model_preload_succeeded model_id=\(selectedModelID, privacy: .public)")
            } catch is CancellationError {
                VoiceFlowLog.transcription.debug("model_preload_cancelled model_id=\(selectedModelID, privacy: .public)")
            } catch {
                VoiceFlowLog.transcription.error("model_preload_failed model_id=\(selectedModelID, privacy: .public) error=\(String(describing: error), privacy: .public)")
            }
            self.preloadTask = nil
        }
    }

    /// Cancels any stale load and begins loading the newly selected model.
    func modelSelectionDidChange() {
        preloadSelectedModel()
    }

    func transcribe(audioURL: URL) async throws -> String {
        let audioID = VoiceFlowLog.audioIdentifier(for: audioURL)
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            VoiceFlowLog.transcription.error("transcription_request_rejected audio_id=\(audioID, privacy: .public) reason=audio_file_missing")
            throw TranscriptionEngineError.audioFileNotFound
        }

        let fileBytes = audioFileSize(at: audioURL)
        VoiceFlowLog.transcription.info("transcription_requested audio_id=\(audioID, privacy: .public) audio_file_bytes=\(fileBytes, privacy: .public)")
        let startedAt = Date()

        do {
            let session = try await session()
            let rawText = try await session.transcribe(audioURL: audioURL)
            let trimmedText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty else {
                VoiceFlowLog.transcription.error("transcription_completed_without_text audio_id=\(audioID, privacy: .public) duration_seconds=\(Date().timeIntervalSince(startedAt), privacy: .public)")
                throw TranscriptionEngineError.noAudioDetected
            }

            VoiceFlowLog.transcription.info("transcription_succeeded audio_id=\(audioID, privacy: .public) duration_seconds=\(Date().timeIntervalSince(startedAt), privacy: .public) result_character_count=\(trimmedText.count, privacy: .public)")
            return rawText
        } catch let error as TranscriptionEngineError {
            VoiceFlowLog.transcription.error("transcription_failed audio_id=\(audioID, privacy: .public) duration_seconds=\(Date().timeIntervalSince(startedAt), privacy: .public) category=\(error.category, privacy: .public)")
            throw error
        } catch {
            VoiceFlowLog.transcription.error("transcription_failed audio_id=\(audioID, privacy: .public) duration_seconds=\(Date().timeIntervalSince(startedAt), privacy: .public) category=runtime error=\(String(describing: error), privacy: .public)")
            throw TranscriptionEngineError.transcriptionFailed(underlying: error)
        }
    }

    private func session() async throws -> WhisperKitSession {
        guard let selectedModelID = modelManager.selectedModelId,
              !selectedModelID.isEmpty else {
            VoiceFlowLog.transcription.error("model_resolution_failed reason=model_not_selected")
            throw TranscriptionEngineError.modelNotSelected
        }

        let modelFolder: URL
        do {
            modelFolder = try modelManager.resolveInstalledModel(id: selectedModelID)
        } catch {
            VoiceFlowLog.transcription.error(
                "model_resolution_failed model_id=\(selectedModelID, privacy: .public) reason=model_preflight_failed error=\(String(describing: error), privacy: .public)"
            )
            throw TranscriptionEngineError.modelNotInstalled
        }

        if let cachedSession, cachedModelID == selectedModelID {
            VoiceFlowLog.transcription.debug("model_session_cache_hit model_id=\(selectedModelID, privacy: .public)")
            VoiceFlowLog.transcription.info("model_ready model_id=\(selectedModelID, privacy: .public) source=session_cache")
            return cachedSession
        }

        if let inFlightLoadTask, inFlightModelID == selectedModelID {
            VoiceFlowLog.transcription.debug("model_load_joined_in_flight model_id=\(selectedModelID, privacy: .public)")
            do {
                return try await inFlightLoadTask.value
            } catch let error as TranscriptionEngineError {
                throw error
            } catch {
                throw TranscriptionEngineError.modelFailedToLoad(underlying: error)
            }
        }

        invalidateCachedSession()
        inFlightLoadTask?.cancel()
        inFlightLoadTask = nil
        inFlightModelID = selectedModelID

        let startedAt = Date()
        VoiceFlowLog.transcription.info("model_load_started model_id=\(selectedModelID, privacy: .public) whisperkit_model_folder=\(modelFolder.path, privacy: .public)")
        let downloadBase = modelManager.downloadBase
        let loadTask = Task.detached(priority: .userInitiated) { [sessionFactory] in
            try await sessionFactory.makeSession(
                modelID: selectedModelID,
                modelFolder: modelFolder,
                downloadBase: downloadBase
            )
        }
        inFlightLoadTask = loadTask

        do {
            let newSession = try await loadTask.value
            let isCurrentLoad = inFlightModelID == selectedModelID
            if modelManager.selectedModelId == selectedModelID {
                cachedSession = newSession
                cachedModelID = selectedModelID
            }
            if isCurrentLoad {
                inFlightLoadTask = nil
                inFlightModelID = nil
            }
            VoiceFlowLog.transcription.info("model_load_succeeded model_id=\(selectedModelID, privacy: .public) duration_seconds=\(Date().timeIntervalSince(startedAt), privacy: .public)")
            VoiceFlowLog.transcription.info("model_ready model_id=\(selectedModelID, privacy: .public) source=new_session")
            return newSession
        } catch is CancellationError {
            if inFlightModelID == selectedModelID {
                inFlightLoadTask = nil
                inFlightModelID = nil
            }
            throw CancellationError()
        } catch {
            if inFlightModelID == selectedModelID {
                inFlightLoadTask = nil
                inFlightModelID = nil
            }
            VoiceFlowLog.transcription.error("model_load_failed model_id=\(selectedModelID, privacy: .public) duration_seconds=\(Date().timeIntervalSince(startedAt), privacy: .public) error=\(String(describing: error), privacy: .public)")
            throw TranscriptionEngineError.modelFailedToLoad(underlying: error)
        }
    }

    func validateModelLoad(modelID: String, modelFolder: URL, downloadBase: URL) async throws {
        let startedAt = Date()
        VoiceFlowLog.transcription.info("model_download_load_validation_started model_id=\(modelID, privacy: .public) whisperkit_model_folder=\(modelFolder.path, privacy: .public)")
        do {
            let loadedSession = try await sessionFactory.makeSession(
                modelID: modelID,
                modelFolder: modelFolder,
                downloadBase: downloadBase
            )
            invalidateCachedSession()
            cachedSession = loadedSession
            cachedModelID = modelID
            VoiceFlowLog.transcription.info("model_download_load_validation_succeeded model_id=\(modelID, privacy: .public) duration_seconds=\(Date().timeIntervalSince(startedAt), privacy: .public)")
            VoiceFlowLog.transcription.info("model_ready model_id=\(modelID, privacy: .public) source=download_validation")
        } catch {
            VoiceFlowLog.transcription.error("model_download_load_validation_failed model_id=\(modelID, privacy: .public) duration_seconds=\(Date().timeIntervalSince(startedAt), privacy: .public) error=\(String(describing: error), privacy: .public)")
            throw error
        }
    }

    private func invalidateCachedSession() {
        if let cachedModelID {
            VoiceFlowLog.transcription.debug("model_session_unloaded model_id=\(cachedModelID, privacy: .public)")
        }
        cachedSession = nil
        cachedModelID = nil
    }

    private func audioFileSize(at url: URL) -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return 0
        }
        return size.int64Value
    }

    enum TranscriptionEngineError: Error {
        case modelNotSelected
        case modelNotInstalled
        case modelFailedToLoad(underlying: Error)
        case audioFileNotFound
        case noAudioDetected
        case transcriptionFailed(underlying: Error)

        var category: String {
            switch self {
            case .modelNotSelected: "model_not_selected"
            case .modelNotInstalled: "model_not_installed"
            case .modelFailedToLoad: "model_load_failed"
            case .audioFileNotFound: "audio_file_missing"
            case .noAudioDetected: "no_audio_detected"
            case .transcriptionFailed: "transcription_runtime_failed"
            }
        }
    }
}

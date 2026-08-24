//
//  ParakeetModelManager.swift
//  VoiceFlow
//
//  Local FluidAudio Parakeet TDT v3 model lifecycle.
//

import CoreML
import FluidAudio
import Foundation
import Observation
import OSLog

@MainActor
protocol ParakeetModelProviding: AnyObject {
    var isInstalled: Bool { get }
    var isSupportedPlatform: Bool { get }
    var modelDirectory: URL { get }
}

@MainActor
@Observable
final class ParakeetModelManager: ParakeetModelProviding {
    static let modelID = "parakeet-tdt-v3"
    static let displayName = "Parakeet TDT 0.6B v3"
    static let repository = "FluidInference/parakeet-tdt-0.6b-v3-coreml"

    static var modelDirectory: URL {
        ModelManager.appModelsDirectory
            .appendingPathComponent("fluidaudio", isDirectory: true)
            .appendingPathComponent("parakeet-tdt-0.6b-v3-coreml", isDirectory: true)
    }

    var modelDirectory: URL { Self.modelDirectory }

    private let fileManager: FileManager
    private(set) var isInstalled: Bool
    private(set) var isLoading = false
    private(set) var progress = 0.0

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.isInstalled = Self.modelsExist(fileManager: fileManager)
    }

    var isSupportedPlatform: Bool {
        #if arch(arm64)
        true
        #else
        false
        #endif
    }

    func refresh() {
        isInstalled = Self.modelsExist(fileManager: fileManager)
    }

    func download(progress: @escaping @MainActor (Double) -> Void) async throws {
        guard isSupportedPlatform else {
            throw ParakeetModelError.unsupportedPlatform
        }

        isLoading = true
        self.progress = 0
        defer { isLoading = false }

        VoiceFlowLog.model.info(
            "parakeet_model_download_started repository=\(Self.repository, privacy: .public) model_directory=\(Self.modelDirectory.path, privacy: .public)"
        )
        do {
            _ = try await AsrModels.download(
                to: Self.modelDirectory,
                version: .v3,
                encoderPrecision: .int8,
                progressHandler: { update in
                    Task { @MainActor in
                        self.progress = min(max(update.fractionCompleted, 0), 1)
                        progress(self.progress)
                    }
                }
            )
            guard Self.modelsExist(fileManager: fileManager) else {
                VoiceFlowLog.model.error("parakeet_model_validation_failed reason=required_files_missing")
                throw ParakeetModelError.invalidModel
            }
            isInstalled = true
            progress(1)
            VoiceFlowLog.model.info("parakeet_model_download_validated model_directory=\(Self.modelDirectory.path, privacy: .public)")
        } catch {
            VoiceFlowLog.model.error("parakeet_model_download_failed error=\(String(describing: error), privacy: .public)")
            throw error
        }
    }

    func delete() throws {
        guard isInstalled else { throw ParakeetModelError.notInstalled }
        try fileManager.removeItem(at: Self.modelDirectory)
        isInstalled = false
        VoiceFlowLog.model.info("parakeet_model_deleted model_directory=\(Self.modelDirectory.path, privacy: .public)")
    }

    static func modelsExist(fileManager: FileManager = .default) -> Bool {
        guard fileManager.fileExists(atPath: modelDirectory.path) else { return false }
        return AsrModels.modelsExist(
            at: modelDirectory,
            version: .v3,
            encoderPrecision: .int8
        )
    }

    enum ParakeetModelError: Error, LocalizedError {
        case unsupportedPlatform
        case invalidModel
        case notInstalled

        var errorDescription: String? {
            switch self {
            case .unsupportedPlatform:
                "Parakeet requires an Apple Silicon Mac."
            case .invalidModel:
                "The Parakeet model is incomplete or invalid."
            case .notInstalled:
                "The Parakeet model is not installed."
            }
        }
    }
}

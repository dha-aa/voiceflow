//
//  WhisperModelCatalog.swift
//  VoiceFlow
//
//  WhisperKit repository definitions and the SDK-backed catalog adapter.
//

import Foundation
import WhisperKit

struct WhisperModelDefinition: Identifiable, Equatable {
    let id: String
    let displayName: String
    let repository: String
    let remoteModelID: String
    let folderName: String
    let language: String?
    let isRecommended: Bool
}

protocol WhisperKitModelLoadValidator: AnyObject {
    func validateModelLoad(modelID: String, modelFolder: URL, downloadBase: URL) async throws
}

protocol WhisperKitModelCatalog {
    func fetchAvailableModels(from repository: String, matching: [String], downloadBase: URL) async throws -> [String]
    func recommendedRemoteModels(from repository: String, downloadBase: URL) async -> ModelSupport
    func download(
        variant: String,
        from repository: String,
        downloadBase: URL,
        progressCallback: @escaping @Sendable (Progress) -> Void
    ) async throws -> URL
}

struct LiveWhisperKitModelCatalog: WhisperKitModelCatalog {
    func fetchAvailableModels(from repository: String, matching: [String], downloadBase: URL) async throws -> [String] {
        try await WhisperKit.fetchAvailableModels(
            from: repository,
            matching: matching,
            downloadBase: downloadBase
        )
    }

    func recommendedRemoteModels(from repository: String, downloadBase: URL) async -> ModelSupport {
        await WhisperKit.recommendedRemoteModels(
            from: repository,
            downloadBase: downloadBase
        )
    }

    func download(
        variant: String,
        from repository: String,
        downloadBase: URL,
        progressCallback: @escaping @Sendable (Progress) -> Void
    ) async throws -> URL {
        try await WhisperKit.download(
            variant: variant,
            downloadBase: downloadBase,
            from: repository,
            progressCallback: progressCallback
        )
    }
}

extension WhisperModelDefinition {
    static let customModels: [WhisperModelDefinition] = [
        WhisperModelDefinition(
            id: "hinglish",
            displayName: "Hindi/Hinglish",
            repository: "nitinh/whisperkit-hinglish-coreml",
            remoteModelID: "Oriserve_Whisper-Hindi2Hinglish-Prime_889MB",
            folderName: "Oriserve_Whisper-Hindi2Hinglish-Prime_889MB",
            language: "en",
            isRecommended: false
        )
    ]
}

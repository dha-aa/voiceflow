//
//  ModelManagerTestSupport.swift
//  VoiceFlowTests
//
//  Shared fixtures and catalog doubles for model lifecycle tests.
//

import Foundation
import WhisperKit
@testable import voiceflow

enum ModelManagerTestFixtures {
    static func makeFixture() throws -> (modelsDirectory: URL, suiteName: String) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("model-manager-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (directory, "voiceflow-tests-\(UUID().uuidString)")
    }

    static func makeManager(
        fixture: (modelsDirectory: URL, suiteName: String),
        catalog: WhisperKitModelCatalog = TestModelCatalog(),
        defaults: UserDefaults? = nil
    ) -> voiceflow.ModelManager {
        voiceflow.ModelManager(
            catalog: catalog,
            modelsDirectory: fixture.modelsDirectory,
            userDefaults: defaults ?? UserDefaults(suiteName: fixture.suiteName)!
        )
    }

    static func makeIncompleteDownloadedModelDirectory(base: URL, variant: String) throws -> URL {
        let directory = base
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)
            .appendingPathComponent("openai_whisper-\(variant)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func makeCustomModelSource(base: URL) throws -> URL {
        let directory = base.appendingPathComponent("Oriserve_Whisper-Hindi2Hinglish-Prime_889MB", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for component in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            try FileManager.default.createDirectory(
                at: directory.appendingPathComponent("\(component).mlmodelc"),
                withIntermediateDirectories: true
            )
            try Data([1]).write(to: directory.appendingPathComponent("\(component).mlmodelc/model.mlmodel"))
        }
        return directory
    }

    static func makeValidDownloadedModelDirectory(base: URL, variant: String) throws -> URL {
        let directory = try makeIncompleteDownloadedModelDirectory(base: base, variant: variant)
        for component in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            try FileManager.default.createDirectory(
                at: directory.appendingPathComponent("\(component).mlmodelc"),
                withIntermediateDirectories: true
            )
            try Data([1]).write(to: directory.appendingPathComponent("\(component).mlmodelc/model.mlmodel"))
        }
        return directory
    }
}

final class TestModelCatalog: WhisperKitModelCatalog {
    let remoteModels: [String]
    let recommended: ModelSupport
    let downloadedVariant: String?

    init(
        remoteModels: [String] = [],
        recommended: ModelSupport = ModelSupport(default: "tiny", supported: []),
        downloadedVariant: String? = nil
    ) {
        self.remoteModels = remoteModels
        self.recommended = recommended
        self.downloadedVariant = downloadedVariant
    }

    func fetchAvailableModels(from repository: String, matching: [String], downloadBase: URL) async throws -> [String] {
        remoteModels
    }

    func recommendedRemoteModels(from repository: String, downloadBase: URL) async -> ModelSupport {
        recommended
    }

    func download(
        variant: String,
        from repository: String,
        downloadBase: URL,
        progressCallback: @escaping @Sendable (Progress) -> Void
    ) async throws -> URL {
        let first = Progress(totalUnitCount: 2)
        first.completedUnitCount = 1
        progressCallback(first)
        let second = Progress(totalUnitCount: 2)
        second.completedUnitCount = 2
        progressCallback(second)

        let directory = try ModelManagerTestFixtures.makeValidDownloadedModelDirectory(
            base: downloadBase,
            variant: downloadedVariant ?? variant
        )
        return directory
    }
}

//
//  TranscriptionEngineTests.swift
//  VoiceFlowTests
//

import Foundation
import XCTest
import WhisperKit
@testable import voiceflow

@MainActor
final class TranscriptionEngineTests: XCTestCase {
    func test_transcriptionEngine_requiresSelectedModel() async throws {
        let manager = makeManager()
        let engine = TranscriptionEngine(
            modelManager: manager,
            sessionFactory: TestSessionFactory()
        )
        let audioURL = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        do {
            _ = try await engine.transcribe(audioURL: audioURL)
            XCTFail("Expected model-not-selected error")
        } catch is TranscriptionEngine.TranscriptionEngineError {
            // Expected.
        }
    }

    func test_transcriptionEngine_rejectsIncompleteInstalledModel() async throws {
        let manager = try makeManagerWithDownloadedModel(valid: false)
        manager.selectModel(id: "tiny.en")
        let engine = TranscriptionEngine(
            modelManager: manager,
            sessionFactory: TestSessionFactory()
        )
        let audioURL = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        do {
            _ = try await engine.transcribe(audioURL: audioURL)
            XCTFail("Expected model-not-installed error")
        } catch let error as TranscriptionEngine.TranscriptionEngineError {
            guard case .modelNotInstalled = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func test_transcriptionEngine_reusesCachedSessionAndForwardsResolvedFolder() async throws {
        let manager = try makeManagerWithDownloadedModel()
        manager.selectModel(id: "tiny.en")
        let expectedFolder = try manager.resolveInstalledModel(id: "tiny.en")
        let factory = TestSessionFactory(result: .success("hello world"))
        let engine = TranscriptionEngine(modelManager: manager, sessionFactory: factory)
        let audioURL = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let first = try await engine.transcribe(audioURL: audioURL)
        let second = try await engine.transcribe(audioURL: audioURL)

        XCTAssertEqual(first, "hello world")
        XCTAssertEqual(second, "hello world")
        XCTAssertEqual(factory.makeCount, 1)
        XCTAssertEqual(factory.modelFolders, [expectedFolder])
    }

    func test_transcriptionEngine_prepareLoadsSelectedModel() async throws {
        let manager = try makeManagerWithDownloadedModel()
        manager.selectModel(id: "tiny.en")
        let factory = TestSessionFactory(result: .success("ready"))
        let engine = TranscriptionEngine(modelManager: manager, sessionFactory: factory)

        try await engine.prepare()

        XCTAssertEqual(factory.makeCount, 1)
    }

    func test_transcriptionEngine_preloadsInBackgroundAndReusesPreloadedSession() async throws {
        let manager = try makeManagerWithDownloadedModel()
        manager.selectModel(id: "tiny.en")
        let factory = TestSessionFactory(result: .success("ready"))
        let engine = TranscriptionEngine(modelManager: manager, sessionFactory: factory)
        let audioURL = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        engine.preloadSelectedModel()
        await waitForFactoryCount(1, factory: factory)
        let result = try await engine.transcribe(audioURL: audioURL)

        XCTAssertEqual(result, "ready")
        XCTAssertEqual(factory.makeCount, 1)
    }

    func test_transcriptionEngine_replacesPreloadedSessionWhenSelectionChanges() async throws {
        let manager = try makeManagerWithDownloadedModels()
        manager.selectModel(id: "tiny.en")
        let factory = TestSessionFactory(result: .success("ready"))
        let engine = TranscriptionEngine(modelManager: manager, sessionFactory: factory)

        engine.preloadSelectedModel()
        await waitForFactoryCount(1, factory: factory)

        manager.selectModel(id: "base")
        engine.modelSelectionDidChange()
        await waitForFactoryCount(2, factory: factory)

        XCTAssertEqual(factory.makeCount, 2)
        XCTAssertEqual(factory.modelIDs, ["tiny.en", "base"])
    }

    func test_transcriptionEngine_returnsErrorForSilentAudio() async throws {
        let manager = try makeManagerWithDownloadedModel()
        manager.selectModel(id: "tiny.en")
        let factory = TestSessionFactory(result: .success("   "))
        let engine = TranscriptionEngine(modelManager: manager, sessionFactory: factory)
        let audioURL = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        do {
            _ = try await engine.transcribe(audioURL: audioURL)
            XCTFail("Expected no-audio error")
        } catch let error as TranscriptionEngine.TranscriptionEngineError {
            guard case .noAudioDetected = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func test_transcriptionEngine_mapsSessionFailure() async throws {
        let manager = try makeManagerWithDownloadedModel()
        manager.selectModel(id: "tiny.en")
        let factory = TestSessionFactory(result: .failure(TestTranscriptionError.failed))
        let engine = TranscriptionEngine(modelManager: manager, sessionFactory: factory)
        let audioURL = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        do {
            _ = try await engine.transcribe(audioURL: audioURL)
            XCTFail("Expected transcription failure")
        } catch let error as TranscriptionEngine.TranscriptionEngineError {
            guard case .transcriptionFailed = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    private func makeManager() -> voiceflow.ModelManager {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("engine-manager-\(UUID().uuidString)", isDirectory: true)
        let defaults = UserDefaults(suiteName: "engine-tests-\(UUID().uuidString)")!
        return voiceflow.ModelManager(
            catalog: EmptyModelCatalog(),
            modelsDirectory: directory,
            userDefaults: defaults
        )
    }

    private func makeManagerWithDownloadedModel(valid: Bool = true) throws -> voiceflow.ModelManager {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("engine-manager-\(UUID().uuidString)", isDirectory: true)
        let defaults = UserDefaults(suiteName: "engine-tests-\(UUID().uuidString)")!
        if !valid {
            defaults.set("tiny.en", forKey: "selectedWhisperModelId")
        }
        let manager = voiceflow.ModelManager(
            catalog: EmptyModelCatalog(),
            modelsDirectory: directory,
            userDefaults: defaults
        )
        let modelDirectory = manager.downloadBase
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)
            .appendingPathComponent("openai_whisper-tiny.en", isDirectory: true)
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        if valid {
            for component in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
                try FileManager.default.createDirectory(
                    at: modelDirectory.appendingPathComponent("\(component).mlmodelc"),
                    withIntermediateDirectories: true
                )
                try Data([1]).write(to: modelDirectory.appendingPathComponent("\(component).mlmodelc/model.mlmodel"))
            }
        }
        return manager
    }

    private func makeManagerWithDownloadedModels() throws -> voiceflow.ModelManager {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("engine-manager-\(UUID().uuidString)", isDirectory: true)
        let defaults = UserDefaults(suiteName: "engine-tests-\(UUID().uuidString)")!
        let manager = voiceflow.ModelManager(
            catalog: EmptyModelCatalog(),
            modelsDirectory: directory,
            userDefaults: defaults
        )

        for modelID in ["tiny.en", "base"] {
            let modelDirectory = manager.downloadBase
                .appendingPathComponent("models", isDirectory: true)
                .appendingPathComponent("argmaxinc", isDirectory: true)
                .appendingPathComponent("whisperkit-coreml", isDirectory: true)
                .appendingPathComponent("openai_whisper-\(modelID)", isDirectory: true)
            try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
            for component in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
                try FileManager.default.createDirectory(
                    at: modelDirectory.appendingPathComponent("\(component).mlmodelc"),
                    withIntermediateDirectories: true
                )
                try Data([1]).write(to: modelDirectory.appendingPathComponent("\(component).mlmodelc/model.mlmodel"))
            }
        }
        return manager
    }

    private func waitForFactoryCount(
        _ expectedCount: Int,
        factory: TestSessionFactory
    ) async {
        for _ in 0..<100 {
            if factory.makeCount >= expectedCount { return }
            await Task.yield()
        }
    }

    private func makeAudioFixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcription-audio-\(UUID().uuidString).wav")
        try Data([0, 1, 2, 3]).write(to: url)
        return url
    }
}

enum TestTranscriptionError: Error {
    case failed
}

final class TestSessionFactory: WhisperKitSessionFactory {
    let result: Result<String, Error>
    private(set) var makeCount = 0
    private(set) var modelFolders: [URL] = []
    private(set) var downloadBases: [URL] = []
    private(set) var modelIDs: [String] = []

    init(result: Result<String, Error> = .success("")) {
        self.result = result
    }

    func makeSession(modelID: String, modelFolder: URL, downloadBase: URL) async throws -> WhisperKitSession {
        makeCount += 1
        modelIDs.append(modelID)
        modelFolders.append(modelFolder)
        downloadBases.append(downloadBase)
        return TestWhisperKitSession(result: result)
    }
}

final class TestWhisperKitSession: WhisperKitSession {
    let result: Result<String, Error>

    init(result: Result<String, Error>) {
        self.result = result
    }

    func transcribe(audioURL: URL) async throws -> String {
        try result.get()
    }
}

final class EmptyModelCatalog: WhisperKitModelCatalog {
    func fetchAvailableModels(from repository: String, matching: [String], downloadBase: URL) async throws -> [String] {
        []
    }

    func recommendedRemoteModels(from repository: String, downloadBase: URL) async -> ModelSupport {
        ModelSupport(default: "tiny", supported: [])
    }

    func download(
        variant: String,
        from repository: String,
        downloadBase: URL,
        progressCallback: @escaping @Sendable (Progress) -> Void
    ) async throws -> URL {
        fatalError("Not used by TranscriptionEngineTests")
    }
}

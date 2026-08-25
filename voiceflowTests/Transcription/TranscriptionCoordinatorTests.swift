//
//  TranscriptionCoordinatorTests.swift
//  VoiceFlowTests
//

import Foundation
import XCTest
@testable import voiceflow

@MainActor
final class TranscriptionCoordinatorTests: XCTestCase {
    func test_coordinator_transitionsToInjectingAndEmitsProcessedText() async throws {
        let manager = try makeManagerWithDownloadedModel()
        manager.selectModel(id: "tiny.en")
        let engine = TranscriptionEngine(
            modelManager: manager,
            sessionFactory: TestSessionFactory(result: .success("  hello   (inaudible) world  "))
        )
        let stateManager = AppStateManager()
        stateManager.transition(to: .processing)
        let isolatedAISettings = UserDefaults(suiteName: "transcription-coordinator-ai-\(UUID().uuidString)")!
        let coordinator = TranscriptionCoordinator(
            stateManager: stateManager,
            engine: engine,
            processor: TextProcessor(),
            claudeProcessor: ClaudeCommandProcessor(userDefaults: isolatedAISettings)
        )
        let callback = expectation(description: "transcription callback")
        var receivedText = ""
        coordinator.onTranscriptionComplete = { text, _ in
            receivedText = text
            callback.fulfill()
        }
        let audioURL = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        await coordinator.transcribe(audioURL: audioURL, targetApp: nil)
        await fulfillment(of: [callback], timeout: 1)

        XCTAssertEqual(receivedText, "hello world")
        XCTAssertEqual(stateManager.currentState, .injecting)
    }

    func test_coordinator_expandsSnippetsLocallyAfterAIWithoutSendingValueToProvider() async throws {
        let manager = try makeManagerWithDownloadedModel()
        manager.selectModel(id: "tiny.en")
        let engine = TranscriptionEngine(
            modelManager: manager,
            sessionFactory: TestSessionFactory(result: .success("Please contact me at my email address."))
        )
        let stateManager = AppStateManager()
        stateManager.transition(to: .processing)
        let defaults = UserDefaults(suiteName: "snippet-ai-\(UUID().uuidString)")!
        defaults.set(true, forKey: AISettings.alwaysUseAIKey)
        let provider = SnippetRecordingAIProviderClient(
            response: "You can contact me at my email address."
        )
        let coordinator = TranscriptionCoordinator(
            stateManager: stateManager,
            engine: engine,
            processor: TextProcessor(),
            claudeProcessor: ClaudeCommandProcessor(
                providerClient: provider,
                keyStore: SnippetTestKeyStore(),
                userDefaults: defaults
            ),
            snippetStore: SnippetStore(snippets: [
                Snippet(name: "My Email", trigger: "my email", value: "user@gmail.com")
            ])
        )
        let callback = expectation(description: "transcription callback")
        var receivedText = ""
        coordinator.onTranscriptionComplete = { text, _ in
            receivedText = text
            callback.fulfill()
        }
        let audioURL = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        await coordinator.transcribe(audioURL: audioURL, targetApp: nil)
        await fulfillment(of: [callback], timeout: 1)

        XCTAssertEqual(receivedText, "You can contact me at user@gmail.com address.")
        XCTAssertEqual(provider.requests.first?.text, "Please contact me at my email address.")
        XCTAssertFalse(provider.requests.contains { $0.text.contains("user@gmail.com") })
    }

    func test_coordinator_mapsMissingModelToModelNotInstalled() async throws {
        let manager = ModelManager(
            catalog: EmptyModelCatalog(),
            modelsDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("missing-model-\(UUID().uuidString)"),
            userDefaults: UserDefaults(suiteName: "missing-model-\(UUID().uuidString)")!
        )
        let engine = TranscriptionEngine(
            modelManager: manager,
            sessionFactory: TestSessionFactory(result: .success("hello"))
        )
        let stateManager = AppStateManager()
        stateManager.transition(to: .processing)
        let coordinator = TranscriptionCoordinator(
            stateManager: stateManager,
            engine: engine,
            processor: TextProcessor()
        )
        let audioURL = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        await coordinator.transcribe(audioURL: audioURL, targetApp: nil)

        XCTAssertEqual(stateManager.currentState, .error(.modelNotInstalled))
    }

    func test_coordinator_doesNotTranscribeOutsideProcessingState() async throws {
        let manager = try makeManagerWithDownloadedModel()
        manager.selectModel(id: "tiny.en")
        let factory = TestSessionFactory(result: .success("hello"))
        let engine = TranscriptionEngine(modelManager: manager, sessionFactory: factory)
        let stateManager = AppStateManager()
        let coordinator = TranscriptionCoordinator(
            stateManager: stateManager,
            engine: engine,
            processor: TextProcessor()
        )
        let audioURL = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        await coordinator.transcribe(audioURL: audioURL, targetApp: nil)

        XCTAssertEqual(stateManager.currentState, .idle)
        XCTAssertEqual(factory.makeCount, 0)
    }

    private func makeManagerWithDownloadedModel() throws -> voiceflow.ModelManager {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("coordinator-manager-\(UUID().uuidString)", isDirectory: true)
        let manager = ModelManager(
            catalog: EmptyModelCatalog(),
            modelsDirectory: directory,
            userDefaults: UserDefaults(suiteName: "coordinator-tests-\(UUID().uuidString)")!
        )
        let modelDirectory = directory
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)
            .appendingPathComponent("openai_whisper-tiny.en", isDirectory: true)
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        for component in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            try FileManager.default.createDirectory(
                at: modelDirectory.appendingPathComponent("\(component).mlmodelc"),
                withIntermediateDirectories: true
            )
        }
        return manager
    }

    private func makeAudioFixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("coordinator-audio-\(UUID().uuidString).wav")
        try Data([0, 1, 2, 3]).write(to: url)
        return url
    }
}

private final class SnippetRecordingAIProviderClient: AIProviderClient {
    let provider: AIProvider = .claude
    let response: String
    private(set) var requests: [AIProcessingRequest] = []

    init(response: String) {
        self.response = response
    }

    func complete(request: AIProcessingRequest, apiKey: String) async throws -> String {
        requests.append(request)
        return response
    }
}

private final class SnippetTestKeyStore: ClaudeAPIKeyStore {
    func read() throws -> String? { "test-key" }
    func save(_ apiKey: String) throws {}
    func remove() throws {}
}

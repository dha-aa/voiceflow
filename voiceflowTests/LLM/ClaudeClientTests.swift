//
//  ClaudeClientTests.swift
//  VoiceFlowTests
//

import XCTest
@testable import voiceflow

@MainActor
final class ClaudeClientTests: XCTestCase {
    func test_parserRecognizesClaudePrefixAndRemovesIt() {
        XCTAssertEqual(ClaudeCommand.parse("Claude, summarize this text")?.prompt, "summarize this text")
        XCTAssertEqual(ClaudeCommand.parse("claude: translate this")?.prompt, "translate this")
        XCTAssertNil(ClaudeCommand.parse("please summarize this"))
    }

    func test_processorDoesNothingForNormalDictation() async throws {
        let defaults = UserDefaults(suiteName: "claude-normal-\(UUID().uuidString)")!
        defaults.set(true, forKey: ClaudeSettings.enabledKey)
        let client = TestClaudeAPIClient(response: "should not be used")
        let keyStore = TestClaudeAPIKeyStore(apiKey: "test-key")
        let processor = ClaudeCommandProcessor(
            apiClient: client,
            keyStore: keyStore,
            userDefaults: defaults
        )

        let result = try await processor.processIfRequested("normal local dictation")

        XCTAssertNil(result)
        XCTAssertEqual(client.callCount, 0)
    }

    func test_processorForwardsOnlyTextAfterClaudePrefix() async throws {
        let defaults = UserDefaults(suiteName: "claude-forward-\(UUID().uuidString)")!
        defaults.set(true, forKey: ClaudeSettings.enabledKey)
        defaults.set("claude-sonnet-5", forKey: ClaudeSettings.modelKey)
        let client = TestClaudeAPIClient(response: "Claude response")
        let keyStore = TestClaudeAPIKeyStore(apiKey: "test-key")
        let processor = ClaudeCommandProcessor(
            apiClient: client,
            keyStore: keyStore,
            userDefaults: defaults
        )

        let result = try await processor.processIfRequested("Claude, make this concise")

        XCTAssertEqual(result, "Claude response")
        XCTAssertEqual(client.callCount, 1)
        XCTAssertEqual(client.receivedPrompt, "make this concise")
        XCTAssertEqual(client.receivedModel, "claude-sonnet-5")
        XCTAssertEqual(client.receivedAPIKey, "test-key")
    }

    func test_processorRejectsClaudeCommandWithoutAPIKey() async {
        let defaults = UserDefaults(suiteName: "claude-no-key-\(UUID().uuidString)")!
        defaults.set(true, forKey: ClaudeSettings.enabledKey)
        let processor = ClaudeCommandProcessor(
            apiClient: TestClaudeAPIClient(response: "unused"),
            keyStore: TestClaudeAPIKeyStore(apiKey: nil),
            userDefaults: defaults
        )

        do {
            _ = try await processor.processIfRequested("Claude, do something")
            XCTFail("Expected missing API key error")
        } catch let error as ClaudeCommandError {
            guard case .notConfigured = error else {
                return XCTFail("Unexpected Claude error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_coordinatorRoutesClaudeCommandAndInjectsResponse() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-coordinator-\(UUID().uuidString)", isDirectory: true)
        let defaults = UserDefaults(suiteName: "claude-coordinator-\(UUID().uuidString)")!
        let manager = ModelManager(
            catalog: EmptyModelCatalog(),
            modelsDirectory: directory,
            userDefaults: defaults
        )
        let modelDirectory = directory
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)
            .appendingPathComponent("openai_whisper-tiny", isDirectory: true)
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        for component in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            try FileManager.default.createDirectory(
                at: modelDirectory.appendingPathComponent("\(component).mlmodelc"),
                withIntermediateDirectories: true
            )
        }
        manager.selectModel(id: "tiny")

        let engine = TranscriptionEngine(
            modelManager: manager,
            sessionFactory: TestSessionFactory(result: .success("Claude, summarize this note"))
        )
        let stateManager = AppStateManager()
        stateManager.transition(to: .processing)
        let claudeDefaults = UserDefaults(suiteName: "claude-coordinator-settings-\(UUID().uuidString)")!
        claudeDefaults.set(true, forKey: ClaudeSettings.enabledKey)
        let client = TestClaudeAPIClient(response: "Summarized note")
        let processor = ClaudeCommandProcessor(
            apiClient: client,
            keyStore: TestClaudeAPIKeyStore(apiKey: "test-key"),
            userDefaults: claudeDefaults
        )
        let coordinator = TranscriptionCoordinator(
            stateManager: stateManager,
            engine: engine,
            processor: TextProcessor(),
            claudeProcessor: processor
        )
        let callback = expectation(description: "Claude response callback")
        var receivedText = ""
        coordinator.onTranscriptionComplete = { text, _ in
            receivedText = text
            callback.fulfill()
        }
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-audio-\(UUID().uuidString).wav")
        try Data([0, 1, 2, 3]).write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        await coordinator.transcribe(audioURL: audioURL, targetApp: nil)
        await fulfillment(of: [callback], timeout: 1)

        XCTAssertEqual(receivedText, "Summarized note")
        XCTAssertEqual(client.receivedPrompt, "summarize this note")
        XCTAssertEqual(stateManager.currentState, .injecting)
    }
}

private final class TestClaudeAPIClient: ClaudeAPIClient {
    let response: String
    private(set) var callCount = 0
    private(set) var receivedPrompt: String?
    private(set) var receivedAPIKey: String?
    private(set) var receivedModel: String?

    init(response: String) {
        self.response = response
    }

    func complete(prompt: String, apiKey: String, model: String) async throws -> String {
        callCount += 1
        receivedPrompt = prompt
        receivedAPIKey = apiKey
        receivedModel = model
        return response
    }
}

private final class TestClaudeAPIKeyStore: ClaudeAPIKeyStore {
    private(set) var storedAPIKey: String?

    init(apiKey: String?) {
        self.storedAPIKey = apiKey
    }

    func read() throws -> String? {
        storedAPIKey
    }

    func save(_ apiKey: String) throws {
        storedAPIKey = apiKey
    }

    func remove() throws {
        storedAPIKey = nil
    }
}

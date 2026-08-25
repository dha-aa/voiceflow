//
//  ClaudeCoordinatorTests.swift
//  VoiceFlowTests
//
//  Transcription coordinator integration with Claude processing.
//

import AppKit
import Foundation
import XCTest
@testable import voiceflow

@MainActor
final class ClaudeCoordinatorTests: XCTestCase {
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
            sessionFactory: TestSessionFactory(result: .success("Jarvis, summarize this note"))
        )
        let stateManager = AppStateManager()
        stateManager.transition(to: .processing)
        let claudeDefaults = UserDefaults(suiteName: "claude-coordinator-settings-\(UUID().uuidString)")!
        claudeDefaults.set(true, forKey: ClaudeSettings.enabledKey)
        claudeDefaults.set("Jarvis", forKey: AISettings.commandPrefixKey)
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
        let providerCallback = expectation(description: "Claude provider callback")
        var receivedText = ""
        var receivedProvider: AIProvider?
        coordinator.onAIProcessingStarted = { provider in
            receivedProvider = provider
            providerCallback.fulfill()
        }
        coordinator.onTranscriptionComplete = { text, _ in
            receivedText = text
            callback.fulfill()
        }
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-audio-\(UUID().uuidString).wav")
        try Data([0, 1, 2, 3]).write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        await coordinator.transcribe(audioURL: audioURL, targetApp: nil)
        await fulfillment(of: [callback, providerCallback], timeout: 1)

        XCTAssertEqual(receivedText, "Summarized note")
        XCTAssertEqual(receivedProvider, .claude)
        XCTAssertEqual(client.receivedPrompt, "summarize this note")
        XCTAssertEqual(stateManager.currentState, .injecting)
    }
}

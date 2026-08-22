//
//  TranscriptionPipelineIntegrationTests.swift
//  VoiceFlowTests
//

import Foundation
import XCTest
@testable import voiceflow

@MainActor
final class TranscriptionPipelineIntegrationTests: XCTestCase {
    func test_fullPipeline_recordingToTranscription() async throws {
        let manager = try makeManagerWithDownloadedModel()
        manager.selectModel(id: "tiny.en")
        let engine = TranscriptionEngine(
            modelManager: manager,
            sessionFactory: TestSessionFactory(result: .success(" testing   one two three "))
        )
        let stateManager = AppStateManager()
        stateManager.transition(to: .processing)
        let coordinator = TranscriptionCoordinator(
            stateManager: stateManager,
            engine: engine,
            processor: TextProcessor()
        )
        let callback = expectation(description: "pipeline transcription callback")
        var receivedText = ""
        coordinator.onTranscriptionComplete = { text, _ in
            receivedText = text
            callback.fulfill()
        }
        let audioURL = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        await coordinator.transcribe(audioURL: audioURL, targetApp: nil)
        await fulfillment(of: [callback], timeout: 1)

        XCTAssertTrue(receivedText.localizedCaseInsensitiveContains("testing"))
        XCTAssertTrue(receivedText.localizedCaseInsensitiveContains("one two three"))
        XCTAssertEqual(stateManager.currentState, .injecting)
    }

    private func makeManagerWithDownloadedModel() throws -> voiceflow.ModelManager {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipeline-manager-\(UUID().uuidString)", isDirectory: true)
        let manager = ModelManager(
            catalog: EmptyModelCatalog(),
            modelsDirectory: directory,
            userDefaults: UserDefaults(suiteName: "pipeline-tests-\(UUID().uuidString)")!
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
            .appendingPathComponent("pipeline-audio-\(UUID().uuidString).wav")
        try Data([0, 1, 2, 3]).write(to: url)
        return url
    }
}

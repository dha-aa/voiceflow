//
//  CorePipelineIntegrationTests.swift
//  VoiceFlowTests
//

import Foundation
import XCTest
@testable import voiceflow

@MainActor
final class CorePipelineIntegrationTests: XCTestCase {
    func test_endToEnd_corePipeline_noUI() async throws {
        let modelDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("injection-pipeline-model-\(UUID().uuidString)", isDirectory: true)
        let modelManager = ModelManager(
            catalog: EmptyModelCatalog(),
            modelsDirectory: modelDirectory,
            userDefaults: UserDefaults(suiteName: "injection-pipeline-\(UUID().uuidString)")!
        )
        let modelFilesDirectory = modelDirectory
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)
            .appendingPathComponent("openai_whisper-tiny.en", isDirectory: true)
        try FileManager.default.createDirectory(at: modelFilesDirectory, withIntermediateDirectories: true)
        for component in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            try FileManager.default.createDirectory(
                at: modelFilesDirectory.appendingPathComponent("\(component).mlmodelc"),
                withIntermediateDirectories: true
            )
        }
        modelManager.selectModel(id: "tiny.en")

        let aiDefaults = UserDefaults(suiteName: "injection-pipeline-ai-\(UUID().uuidString)")!
        let transcriptionCoordinator = TranscriptionCoordinator(
            stateManager: stateManager,
            engine: TranscriptionEngine(
                modelManager: modelManager,
                sessionFactory: TestSessionFactory(result: .success(" hello pipeline test "))
            ),
            processor: TextProcessor(),
            claudeProcessor: ClaudeCommandProcessor(userDefaults: aiDefaults)
        )
        let injector = TestTextInjector()
        let injectionCoordinator = InjectionCoordinator(
            stateManager: stateManager,
            injector: injector
        )
        let injectionComplete = expectation(description: "injection complete")

        transcriptionCoordinator.onTranscriptionComplete = { text, targetApp in
            Task { @MainActor in
                await injectionCoordinator.inject(text: text, targetApp: targetApp)
                injectionComplete.fulfill()
            }
        }

        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("injection-pipeline-audio-\(UUID().uuidString).wav")
        try Data([0, 1, 2, 3]).write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        stateManager.transition(to: .processing)

        await transcriptionCoordinator.transcribe(audioURL: audioURL, targetApp: nil)
        await fulfillment(of: [injectionComplete], timeout: 1)

        XCTAssertEqual(stateManager.currentState, .idle)
        XCTAssertEqual(injector.injectedTexts.map(\.text), ["hello pipeline test"])
    }

    private let stateManager = AppStateManager()
}

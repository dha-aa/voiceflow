//
//  ParakeetTranscriptionEngineTests.swift
//  VoiceFlowTests
//

import Foundation
import XCTest
@testable import voiceflow

@MainActor
final class ParakeetTranscriptionEngineTests: XCTestCase {
    func test_transcribe_reusesLoadedParakeetSession() async throws {
        let provider = TestParakeetModelProvider(isInstalled: true)
        let factory = TestParakeetSessionFactory(result: .success("hello from parakeet"))
        let engine = ParakeetTranscriptionEngine(modelManager: provider, sessionFactory: factory)
        let audioURL = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let first = try await engine.transcribe(audioURL: audioURL)
        let second = try await engine.transcribe(audioURL: audioURL)

        XCTAssertEqual(first, "hello from parakeet")
        XCTAssertEqual(second, "hello from parakeet")
        XCTAssertEqual(factory.makeCount, 1)
        XCTAssertEqual(factory.modelFolders, [provider.modelDirectory])
    }

    func test_transcribe_requiresInstalledParakeetModel() async throws {
        let provider = TestParakeetModelProvider(isInstalled: false)
        let engine = ParakeetTranscriptionEngine(
            modelManager: provider,
            sessionFactory: TestParakeetSessionFactory(result: .success("unused"))
        )
        let audioURL = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        do {
            _ = try await engine.transcribe(audioURL: audioURL)
            XCTFail("Expected model-not-installed error")
        } catch let error as SpeechTranscriptionError {
            guard case .modelNotInstalled = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func test_prepareLoadsInstalledParakeetModel() async throws {
        let provider = TestParakeetModelProvider(isInstalled: true)
        let factory = TestParakeetSessionFactory(result: .success("ready"))
        let engine = ParakeetTranscriptionEngine(modelManager: provider, sessionFactory: factory)

        try await engine.prepare()

        XCTAssertEqual(factory.makeCount, 1)
    }

    func test_transcribeMapsSessionFailure() async throws {
        let provider = TestParakeetModelProvider(isInstalled: true)
        let factory = TestParakeetSessionFactory(
            result: .success("unused"),
            transcriptionError: TestParakeetError.failed
        )
        let engine = ParakeetTranscriptionEngine(modelManager: provider, sessionFactory: factory)
        let audioURL = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        do {
            _ = try await engine.transcribe(audioURL: audioURL)
            XCTFail("Expected transcription failure")
        } catch let error as SpeechTranscriptionError {
            guard case .transcriptionFailed = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    private func makeAudioFixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("parakeet-audio-\(UUID().uuidString).wav")
        try Data([0, 1, 2, 3]).write(to: url)
        return url
    }
}

@MainActor
private final class TestParakeetModelProvider: ParakeetModelProviding {
    let modelDirectory: URL
    let isSupportedPlatform: Bool
    var isInstalled: Bool

    init(isInstalled: Bool, isSupportedPlatform: Bool = true) {
        self.modelDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("parakeet-model-\(UUID().uuidString)", isDirectory: true)
        self.isSupportedPlatform = isSupportedPlatform
        self.isInstalled = isInstalled
    }
}

private final class TestParakeetSessionFactory: ParakeetSessionFactory {
    let result: Result<String, Error>
    let transcriptionError: Error?
    private(set) var makeCount = 0
    private(set) var modelFolders: [URL] = []

    init(result: Result<String, Error>, transcriptionError: Error? = nil) {
        self.result = result
        self.transcriptionError = transcriptionError
    }

    func makeSession(modelFolder: URL) async throws -> ParakeetSession {
        makeCount += 1
        modelFolders.append(modelFolder)
        switch result {
        case .success(let text):
            return TestParakeetSession(text: text, error: transcriptionError)
        case .failure(let error):
            throw error
        }
    }
}

private final class TestParakeetSession: ParakeetSession {
    let text: String
    let error: Error?

    init(text: String, error: Error? = nil) {
        self.text = text
        self.error = error
    }

    func transcribe(audioURL: URL) async throws -> String {
        if let error { throw error }
        return text
    }
}

private enum TestParakeetError: Error {
    case failed
}

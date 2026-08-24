//
//  ParakeetTranscriptionEngineTests.swift
//  VoiceFlowTests
//

import Foundation
import XCTest
@testable import voiceflow

@MainActor
final class ParakeetTranscriptionEngineTests: XCTestCase {
    func test_variantSelectionPersists() {
        let suiteName = "ParakeetModelManagerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = ParakeetModelManager(userDefaults: defaults)
        manager.selectVariant(.v2)
        let restored = ParakeetModelManager(userDefaults: defaults)

        XCTAssertEqual(restored.selectedVariant, .v2)
        XCTAssertEqual(restored.modelDirectory.lastPathComponent, "parakeet-tdt-0.6b-v2")
    }

    func test_validationRequiresExactV3CoreMLArtifacts() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("parakeet-v3-validation-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try createCompiledBundle(named: "Encoder.mlmodelc", at: directory)
        try createCompiledBundle(named: "Decoder.mlmodelc", at: directory)
        try createCompiledBundle(named: "JointDecisionv3.mlmodelc", at: directory)
        try Data("{}".utf8).write(to: directory.appendingPathComponent("parakeet_vocab.json"))

        let validation = ParakeetModelManager.validation(at: directory, variant: .v3)

        guard case .missingArtifacts(let missing) = validation.status else {
            return XCTFail("Expected the v3 preprocessor artifact to be reported missing")
        }
        XCTAssertEqual(missing, ["Preprocessor.mlmodelc"])
    }

    func test_validationRejectsNVIDIASourceRepository() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("parakeet-nvidia-source-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("source".utf8).write(to: directory.appendingPathComponent("model.safetensors"))
        try Data("source".utf8).write(to: directory.appendingPathComponent("config.json"))

        let validation = ParakeetModelManager.validation(at: directory, variant: .v3)

        guard case .unsupportedSourceFormat(let markers) = validation.status else {
            return XCTFail("Expected raw NVIDIA source format to be rejected")
        }
        XCTAssertEqual(markers, ["model.safetensors"])
    }

    func test_validationAcceptsCompleteV2CoreMLStructure() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("parakeet-v2-validation-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in ["Preprocessor.mlmodelc", "Encoder.mlmodelc", "Decoder.mlmodelc", "JointDecision.mlmodelc"] {
            try createCompiledBundle(named: name, at: directory)
        }
        try Data("{}".utf8).write(to: directory.appendingPathComponent("parakeet_vocab.json"))

        let validation = ParakeetModelManager.validation(at: directory, variant: .v2)

        XCTAssertTrue(validation.isComplete)
    }

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
        XCTAssertEqual(factory.variants, [provider.selectedVariant])
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

    private func createCompiledBundle(named name: String, at directory: URL) throws {
        let bundle = directory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        for content in ["model.mil", "metadata.json", "coremldata.bin"] {
            try Data(content.utf8).write(to: bundle.appendingPathComponent(content))
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
    let selectedVariant: ParakeetModelVariant
    var isInstalled: Bool

    init(
        isInstalled: Bool,
        isSupportedPlatform: Bool = true,
        selectedVariant: ParakeetModelVariant = .v3
    ) {
        self.modelDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("parakeet-model-\(UUID().uuidString)", isDirectory: true)
        self.isSupportedPlatform = isSupportedPlatform
        self.selectedVariant = selectedVariant
        self.isInstalled = isInstalled
    }
}

private final class TestParakeetSessionFactory: ParakeetSessionFactory {
    let result: Result<String, Error>
    let transcriptionError: Error?
    private(set) var makeCount = 0
    private(set) var modelFolders: [URL] = []
    private(set) var variants: [ParakeetModelVariant] = []

    init(result: Result<String, Error>, transcriptionError: Error? = nil) {
        self.result = result
        self.transcriptionError = transcriptionError
    }

    func makeSession(modelFolder: URL, variant: ParakeetModelVariant) async throws -> ParakeetSession {
        makeCount += 1
        modelFolders.append(modelFolder)
        variants.append(variant)
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

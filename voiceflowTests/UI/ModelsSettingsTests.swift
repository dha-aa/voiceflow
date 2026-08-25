//
//  ModelsSettingsTests.swift
//  VoiceFlowTests
//
//  Model catalog, download, validation, and deletion behavior.
//

import Foundation
import XCTest
import WhisperKit
@testable import voiceflow

@MainActor
final class ModelsSettingsViewTests: XCTestCase {
    func test_catalogRefresh_hasDedicatedStateAndClearsAfterFailure() async {
        let fixture = try! makeFixture()
        let manager = voiceflow.ModelManager(
            catalog: FailingRefreshCatalog(),
            modelsDirectory: fixture.modelsDirectory,
            userDefaults: UserDefaults(suiteName: fixture.suiteName)!
        )

        XCTAssertFalse(manager.isRefreshing)
        do {
            try await manager.refreshModels()
            XCTFail("Expected catalog refresh to fail")
        } catch {
            XCTAssertFalse(manager.isRefreshing)
        }
    }

    func test_modelsView_showsInstalledAndAvailableModelsFromManager() async throws {
        let fixture = try makeFixture()
        _ = try makeValidModel(base: fixture.modelsDirectory, variant: "tiny.en")
        let catalog = TestModelCatalog(
            remoteModels: ["openai_whisper-tiny.en", "openai_whisper-base.en"],
            recommended: ModelSupport(
                default: "openai_whisper-tiny.en",
                supported: ["openai_whisper-tiny.en"]
            )
        )
        let manager = voiceflow.ModelManager(
            catalog: catalog,
            modelsDirectory: fixture.modelsDirectory,
            userDefaults: UserDefaults(suiteName: fixture.suiteName)!
        )

        try await manager.refreshModels()

        XCTAssertEqual(manager.availableModels.count, 2)
        XCTAssertTrue(manager.availableModels.first { $0.id == "tiny.en" }?.isDownloaded == true)
        XCTAssertTrue(manager.availableModels.first { $0.id == "base.en" }?.isDownloaded == false)
        _ = ModelsSettingsView(
            modelManager: manager,
            downloadCoordinator: ModelDownloadCoordinator(modelManager: manager),
            speechRecognitionSettings: SpeechRecognitionSettings(userDefaults: UserDefaults(suiteName: "models-engine-\(UUID().uuidString)")!),
            parakeetModelManager: ParakeetModelManager()
        )
    }

    func test_modelsView_activeModelSelectionPersists() throws {
        let fixture = try makeFixture()
        _ = try makeValidModel(base: fixture.modelsDirectory, variant: "tiny.en")
        let defaults = UserDefaults(suiteName: fixture.suiteName)!
        let manager = voiceflow.ModelManager(
            modelsDirectory: fixture.modelsDirectory,
            userDefaults: defaults
        )

        manager.selectModel(id: "tiny.en")

        XCTAssertEqual(manager.selectedModelId, "tiny.en")
        XCTAssertEqual(defaults.string(forKey: "selectedWhisperModelId"), "tiny.en")
    }

    func test_modelsView_downloadReportsProgressAndMarksModelInstalled() async throws {
        let fixture = try makeFixture()
        let manager = voiceflow.ModelManager(
            catalog: TestModelCatalog(
                remoteModels: ["openai_whisper-base"],
                downloadedVariant: "base"
            ),
            modelsDirectory: fixture.modelsDirectory,
            userDefaults: UserDefaults(suiteName: fixture.suiteName)!
        )
        try await manager.refreshModels()
        var progress: [Double] = []

        try await manager.downloadModel(id: "base") { progress.append($0) }

        XCTAssertEqual(progress, [0.5, 1.0])
        XCTAssertTrue(manager.isModelDownloaded(variantId: "base"))
    }

    func test_downloadCoordinator_keepsProgressOutsideTheModelsView() async throws {
        let fixture = try makeFixture()
        let manager = voiceflow.ModelManager(
            catalog: SlowModelCatalog(),
            modelsDirectory: fixture.modelsDirectory,
            userDefaults: UserDefaults(suiteName: fixture.suiteName)!
        )
        try await manager.refreshModels()
        let coordinator = ModelDownloadCoordinator(modelManager: manager)

        coordinator.startDownload(id: "base")
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(coordinator.activeModelID, "base")
        XCTAssertTrue(coordinator.isDownloading)
        XCTAssertGreaterThan(coordinator.progress, 0)

        _ = ModelsSettingsView(
            modelManager: manager,
            downloadCoordinator: coordinator,
            speechRecognitionSettings: SpeechRecognitionSettings(userDefaults: UserDefaults(suiteName: "models-download-engine-\(UUID().uuidString)")!),
            parakeetModelManager: ParakeetModelManager()
        )
        XCTAssertEqual(coordinator.activeModelID, "base")
        XCTAssertTrue(coordinator.isDownloading)

        coordinator.cancelDownload()
        try await waitUntilFinished(coordinator)
        XCTAssertFalse(coordinator.isDownloading)
    }

    func test_downloadCoordinator_completesDownloadAndClearsTransientState() async throws {
        let fixture = try makeFixture()
        let manager = voiceflow.ModelManager(
            catalog: SlowModelCatalog(),
            modelsDirectory: fixture.modelsDirectory,
            userDefaults: UserDefaults(suiteName: fixture.suiteName)!
        )
        try await manager.refreshModels()
        let coordinator = ModelDownloadCoordinator(modelManager: manager)

        coordinator.startDownload(id: "base")
        try await waitUntilFinished(coordinator)

        XCTAssertFalse(coordinator.isDownloading)
        XCTAssertNil(coordinator.errorMessage)
        XCTAssertTrue(manager.isModelDownloaded(variantId: "base"))
    }

    func test_downloadCoordinator_validatesTheExactDownloadedFolderBeforeDetection() async throws {
        let fixture = try makeFixture()
        let manager = voiceflow.ModelManager(
            catalog: SlowModelCatalog(),
            modelsDirectory: fixture.modelsDirectory,
            userDefaults: UserDefaults(suiteName: fixture.suiteName)!
        )
        try await manager.refreshModels()
        let validator = RecordingModelLoadValidator()
        manager.modelLoadValidator = validator

        try await manager.downloadModel(id: "base") { _ in }

        XCTAssertEqual(validator.loadedModelIDs, ["base"])
        XCTAssertEqual(validator.loadedFolders.count, 1)
        XCTAssertEqual(
            validator.loadedFolders.first?.lastPathComponent,
            "openai_whisper-base"
        )
        XCTAssertTrue(manager.availableModels.first { $0.id == "base" }?.isDownloaded == true)
        XCTAssertTrue(manager.isModelDownloaded(variantId: "base"))
    }

    func test_downloadCoordinator_doesNotMarkModelInstalledWhenWhisperKitLoadFails() async throws {
        let fixture = try makeFixture()
        let manager = voiceflow.ModelManager(
            catalog: SlowModelCatalog(),
            modelsDirectory: fixture.modelsDirectory,
            userDefaults: UserDefaults(suiteName: fixture.suiteName)!
        )
        try await manager.refreshModels()
        let validator = RecordingModelLoadValidator(shouldFail: true)
        manager.modelLoadValidator = validator

        do {
            try await manager.downloadModel(id: "base") { _ in }
            XCTFail("Expected post-download model-load validation to fail")
        } catch let error as voiceflow.ModelManager.ModelManagerError {
            XCTAssertEqual(error, .modelLoadFailed)
        }

        XCTAssertFalse(manager.isModelDownloaded(variantId: "base"))
        XCTAssertTrue(manager.availableModels.first { $0.id == "base" }?.isDownloaded == false)
        let downloadedPath = fixture.modelsDirectory
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)
            .appendingPathComponent("openai_whisper-base", isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: downloadedPath.path))
    }

    func test_modelsView_deleteActiveModelIsBlockedBeforeConfirmation() throws {
        let fixture = try makeFixture()
        _ = try makeValidModel(base: fixture.modelsDirectory, variant: "tiny.en")
        let manager = voiceflow.ModelManager(
            modelsDirectory: fixture.modelsDirectory,
            userDefaults: UserDefaults(suiteName: fixture.suiteName)!
        )
        manager.selectModel(id: "tiny.en")

        XCTAssertThrowsError(try manager.deleteModel(id: "tiny.en")) { error in
            XCTAssertEqual(error as? voiceflow.ModelManager.ModelManagerError, .cannotDeleteActiveModel)
        }
    }

    private func makeFixture() throws -> (modelsDirectory: URL, suiteName: String) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("settings-models-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (directory, "settings-tests-\(UUID().uuidString)")
    }

    private func waitUntilFinished(_ coordinator: ModelDownloadCoordinator) async throws {
        for _ in 0..<100 {
            if !coordinator.isDownloading { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Download did not finish within the test timeout")
    }

    private func makeValidModel(base: URL, variant: String) throws -> URL {
        let directory = base
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)
            .appendingPathComponent("openai_whisper-\(variant)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for component in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            let componentDirectory = directory.appendingPathComponent("\(component).mlmodelc", isDirectory: true)
            try FileManager.default.createDirectory(at: componentDirectory, withIntermediateDirectories: true)
            try Data([1]).write(to: componentDirectory.appendingPathComponent("model.mlmodel"))
        }
        return directory
    }
}

private final class RecordingModelLoadValidator: WhisperKitModelLoadValidator {
    let shouldFail: Bool
    private(set) var loadedModelIDs: [String] = []
    private(set) var loadedFolders: [URL] = []

    init(shouldFail: Bool = false) {
        self.shouldFail = shouldFail
    }

    func validateModelLoad(modelID: String, modelFolder: URL, downloadBase: URL) async throws {
        loadedModelIDs.append(modelID)
        loadedFolders.append(modelFolder)
        if shouldFail {
            throw NSError(domain: "SettingsTests", code: 1)
        }
    }
}

private final class FailingRefreshCatalog: WhisperKitModelCatalog {
    enum Failure: Error { case unavailable }

    func fetchAvailableModels(from repository: String, matching: [String], downloadBase: URL) async throws -> [String] {
        throw Failure.unavailable
    }

    func recommendedRemoteModels(from repository: String, downloadBase: URL) async -> ModelSupport {
        ModelSupport(default: "", supported: [])
    }

    func download(
        variant: String,
        from repository: String,
        downloadBase: URL,
        progressCallback: @escaping @Sendable (Progress) -> Void
    ) async throws -> URL {
        throw Failure.unavailable
    }
}

private final class SlowModelCatalog: WhisperKitModelCatalog {
    func fetchAvailableModels(from repository: String, matching: [String], downloadBase: URL) async throws -> [String] {
        ["openai_whisper-base"]
    }

    func recommendedRemoteModels(from repository: String, downloadBase: URL) async -> ModelSupport {
        ModelSupport(default: "openai_whisper-base", supported: ["openai_whisper-base"])
    }

    func download(
        variant: String,
        from repository: String,
        downloadBase: URL,
        progressCallback: @escaping @Sendable (Progress) -> Void
    ) async throws -> URL {
        for step in 1...20 {
            try await Task.sleep(for: .milliseconds(10))
            let update = Progress(totalUnitCount: 20)
            update.completedUnitCount = Int64(step)
            progressCallback(update)
        }

        let directory = downloadBase
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)
            .appendingPathComponent("openai_whisper-\(variant)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for component in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            let componentDirectory = directory.appendingPathComponent("\(component).mlmodelc", isDirectory: true)
            try FileManager.default.createDirectory(at: componentDirectory, withIntermediateDirectories: true)
            try Data([1]).write(to: componentDirectory.appendingPathComponent("model.mlmodel"))
        }
        return directory
    }
}

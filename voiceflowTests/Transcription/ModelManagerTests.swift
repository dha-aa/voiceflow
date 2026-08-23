//
//  ModelManagerTests.swift
//  VoiceFlowTests
//

import Foundation
import XCTest
import WhisperKit
@testable import voiceflow

@MainActor
final class ModelManagerTests: XCTestCase {
    func test_modelManager_initialState_noModelsLoaded() throws {
        let fixture = try makeFixture()
        let manager = makeManager(fixture: fixture)

        XCTAssertTrue(manager.availableModels.isEmpty)
        XCTAssertNil(manager.selectedModelId)
    }

    func test_modelManager_selectModel_requiresInstalledValidModel() throws {
        let fixture = try makeFixture()
        let manager = makeManager(fixture: fixture)

        manager.selectModel(id: "tiny")

        XCTAssertNil(manager.selectedModelId)
    }

    func test_modelManager_selectModel_updatesAndPersistsValidModel() throws {
        let fixture = try makeFixture()
        let directory = try makeValidDownloadedModelDirectory(base: fixture.modelsDirectory, variant: "tiny")
        let defaults = UserDefaults(suiteName: fixture.suiteName)!
        let firstManager = makeManager(fixture: fixture, defaults: defaults)

        firstManager.selectModel(id: "tiny")

        XCTAssertEqual(firstManager.selectedModelId, "tiny")
        XCTAssertEqual(try firstManager.resolveInstalledModel(id: "tiny"), directory)

        let secondManager = makeManager(fixture: fixture, defaults: defaults)
        XCTAssertEqual(secondManager.selectedModelId, "tiny")
    }

    func test_modelManager_refreshModels_discoversOnlyValidDownloadedModels() async throws {
        let fixture = try makeFixture()
        _ = try makeValidDownloadedModelDirectory(base: fixture.modelsDirectory, variant: "tiny")
        let incomplete = try makeIncompleteDownloadedModelDirectory(base: fixture.modelsDirectory, variant: "base.en")
        try Data([1]).write(to: incomplete.appendingPathComponent("AudioEncoder.mlmodelc"))
        let catalog = TestModelCatalog(
            remoteModels: ["openai_whisper-tiny", "openai_whisper-base.en"],
            recommended: ModelSupport(default: "openai_whisper-tiny", supported: ["openai_whisper-tiny"])
        )
        let manager = makeManager(fixture: fixture, catalog: catalog)

        try await manager.refreshModels()

        let tiny = try XCTUnwrap(manager.availableModels.first { $0.id == "tiny" })
        let base = try XCTUnwrap(manager.availableModels.first { $0.id == "base.en" })
        XCTAssertTrue(tiny.isDownloaded)
        XCTAssertGreaterThan(tiny.sizeOnDisk ?? 0, 0)
        XCTAssertTrue(tiny.isRecommended)
        XCTAssertFalse(base.isDownloaded)
        XCTAssertNil(base.sizeOnDisk)
        XCTAssertFalse(base.isRecommended)
        XCTAssertEqual(tiny.displayName, "Tiny")
    }

    func test_modelManager_preflightResolvesBaseVariantFromCanonicalDirectory() throws {
        let fixture = try makeFixture()
        let directory = try makeValidDownloadedModelDirectory(base: fixture.modelsDirectory, variant: "base")
        let manager = makeManager(fixture: fixture)

        let report = manager.preflight(modelID: "base")

        XCTAssertTrue(report.isValid, report.diagnosticDescription)
        XCTAssertEqual(report.whisperKitModelFolder, directory)
        XCTAssertEqual(report.validationFailureReason, "none")
    }

    func test_modelManager_resolvesExactlyOneCanonicalDirectory() throws {
        let fixture = try makeFixture()
        let directory = try makeValidDownloadedModelDirectory(base: fixture.modelsDirectory, variant: "tiny.en")
        let manager = makeManager(fixture: fixture)

        let report = manager.preflight(modelID: "tiny.en")

        XCTAssertTrue(report.isValid)
        XCTAssertEqual(report.resolvedModelDirectory, directory)
        XCTAssertEqual(report.whisperKitModelFolder, directory)
        XCTAssertTrue(report.modelDirectoryIsInsideModelsRoot)
        XCTAssertTrue(report.modelDirectoryHasNoSymlink)
        XCTAssertTrue(report.modelIDMatchesDirectory)
    }

    func test_modelManager_preflightDiagnosticsReportEachExpectedComponent() throws {
        let fixture = try makeFixture()
        let directory = try makeValidDownloadedModelDirectory(base: fixture.modelsDirectory, variant: "tiny.en")
        let manager = makeManager(fixture: fixture)

        let report = manager.preflight(modelID: "tiny.en")

        XCTAssertEqual(report.componentDiagnostics.map(\.name), ["MelSpectrogram", "AudioEncoder", "TextDecoder"])
        XCTAssertTrue(report.componentDiagnostics.allSatisfy(\.exists))
        XCTAssertTrue(report.diagnosticDescription.contains("Validation Failure Reason: none"))
        XCTAssertTrue(report.diagnosticDescription.contains(directory.path))
    }

    func test_modelManager_preflightRejectsNestedModelDirectory() throws {
        let fixture = try makeFixture()
        let directory = try makeValidDownloadedModelDirectory(base: fixture.modelsDirectory, variant: "tiny.en")
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("openai_whisper-tiny.en", isDirectory: true),
            withIntermediateDirectories: true
        )
        let manager = makeManager(fixture: fixture)

        let report = manager.preflight(modelID: "tiny.en")

        XCTAssertFalse(report.isValid)
        XCTAssertEqual(report.validationFailureReason, "nested_model_directory")
        XCTAssertEqual(
            report.nestedModelDirectory?.lastPathComponent,
            "openai_whisper-tiny.en"
        )
    }

    func test_modelManager_preflightDescriptionReportsPass() throws {
        let fixture = try makeFixture()
        _ = try makeValidDownloadedModelDirectory(base: fixture.modelsDirectory, variant: "tiny.en")
        let manager = makeManager(fixture: fixture)

        let report = manager.preflight(modelID: "tiny.en")

        XCTAssertTrue(report.diagnosticDescription.contains("RESULT: PASS"))
        XCTAssertTrue(report.diagnosticDescription.contains("WhisperKit Configuration: PASS"))
    }

    func test_modelManager_preflightRejectsMissingModel() throws {
        let fixture = try makeFixture()
        let manager = makeManager(fixture: fixture)

        let report = manager.preflight(modelID: "tiny.en")

        XCTAssertFalse(report.isValid)
        XCTAssertFalse(report.modelDirectoryExists)
        XCTAssertNil(report.resolvedModelDirectory)
        XCTAssertThrowsError(try manager.resolveInstalledModel(id: "tiny.en"))
    }

    func test_modelManager_preflightRejectsIncompleteModel() throws {
        let fixture = try makeFixture()
        let directory = try makeIncompleteDownloadedModelDirectory(base: fixture.modelsDirectory, variant: "tiny.en")
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("AudioEncoder.mlmodelc"), withIntermediateDirectories: true)
        let manager = makeManager(fixture: fixture)

        let report = manager.preflight(modelID: "tiny.en")

        XCTAssertFalse(report.isValid)
        XCTAssertTrue(report.modelDirectoryExists)
        XCTAssertFalse(report.expectedModelComponentsPresent)
        XCTAssertEqual(report.validationFailureReason, "required_coreml_component_missing")
        XCTAssertTrue(report.componentDiagnostics.contains {
            $0.name == "TextDecoder" && !$0.exists && !$0.compiledModelExists && !$0.packageExists
        })
    }

    func test_modelManager_downloadModel_validatesAndRefreshesLocalState() async throws {
        let fixture = try makeFixture()
        let catalog = TestModelCatalog(
            remoteModels: ["openai_whisper-tiny"],
            recommended: ModelSupport(default: "openai_whisper-tiny", supported: ["openai_whisper-tiny"]),
            downloadedVariant: "tiny"
        )
        let manager = makeManager(fixture: fixture, catalog: catalog)
        try await manager.refreshModels()
        var progressValues: [Double] = []

        try await manager.downloadModel(id: "tiny") { progressValues.append($0) }

        XCTAssertEqual(progressValues, [0.5, 1.0])
        XCTAssertTrue(manager.isModelDownloaded(variantId: "tiny"))
        XCTAssertTrue(manager.availableModels.first?.isDownloaded == true)
        XCTAssertNoThrow(try manager.resolveInstalledModel(id: "tiny"))
    }

    func test_modelManager_importsCustomModelFromSelectedFolder() async throws {
        let fixture = try makeFixture()
        let source = try makeCustomModelSource(base: fixture.modelsDirectory)
        let manager = makeManager(fixture: fixture)

        try await manager.importCustomModel(from: source)

        let installed = try manager.resolveInstalledModel(id: "hinglish")
        XCTAssertEqual(installed.lastPathComponent, "Oriserve_Whisper-Hindi2Hinglish-Prime_889MB")
        XCTAssertTrue(manager.isModelDownloaded(variantId: "hinglish"))
        XCTAssertEqual(manager.whisperKitModelID(for: "hinglish"), "Oriserve_Whisper-Hindi2Hinglish-Prime_889MB")
        XCTAssertEqual(manager.availableModels.first(where: { $0.id == "hinglish" })?.displayName, "Hindi/Hinglish")
    }

    func test_modelManager_importRejectsWrongFolderName() async throws {
        let fixture = try makeFixture()
        let source = fixture.modelsDirectory.appendingPathComponent("not-a-whisper-model", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let manager = makeManager(fixture: fixture)

        do {
            try await manager.importCustomModel(from: source)
            XCTFail("Expected invalid custom model directory")
        } catch let error as voiceflow.ModelManager.ModelManagerError {
            XCTAssertEqual(error, .invalidModelDirectory)
        }
    }

    func test_modelManager_deleteModel_blocksActiveModel() throws {
        let fixture = try makeFixture()
        _ = try makeValidDownloadedModelDirectory(base: fixture.modelsDirectory, variant: "tiny")
        let manager = makeManager(fixture: fixture)
        manager.selectModel(id: "tiny")

        XCTAssertThrowsError(try manager.deleteModel(id: "tiny")) { error in
            XCTAssertEqual(error as? voiceflow.ModelManager.ModelManagerError, .cannotDeleteActiveModel)
        }
    }

    func test_modelManager_deleteModel_removesInactiveModel() throws {
        let fixture = try makeFixture()
        let directory = try makeValidDownloadedModelDirectory(base: fixture.modelsDirectory, variant: "tiny")
        let manager = makeManager(fixture: fixture)

        try manager.deleteModel(id: "tiny")

        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertFalse(manager.isModelDownloaded(variantId: "tiny"))
    }

    private func makeFixture() throws -> (modelsDirectory: URL, suiteName: String) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("model-manager-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (directory, "voiceflow-tests-\(UUID().uuidString)")
    }

    private func makeManager(
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

    private func makeIncompleteDownloadedModelDirectory(base: URL, variant: String) throws -> URL {
        let directory = base
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)
            .appendingPathComponent("openai_whisper-\(variant)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeCustomModelSource(base: URL) throws -> URL {
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

    private func makeValidDownloadedModelDirectory(base: URL, variant: String) throws -> URL {
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

        let directory = downloadBase
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)
            .appendingPathComponent("openai_whisper-\(downloadedVariant ?? variant)", isDirectory: true)
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
}

//
//  ModelManagerLifecycleTests.swift
//  VoiceFlowTests
//
//  WhisperKit model selection, download, import, and deletion behavior.
//

import Foundation
import XCTest
import WhisperKit
@testable import voiceflow

@MainActor
final class ModelManagerLifecycleTests: XCTestCase {
    func test_modelManager_initialState_noModelsLoaded() throws {
        let fixture = try ModelManagerTestFixtures.makeFixture()
        let manager = ModelManagerTestFixtures.makeManager(fixture: fixture)

        XCTAssertTrue(manager.availableModels.isEmpty)
        XCTAssertNil(manager.selectedModelId)
    }

    func test_modelManager_selectModel_requiresInstalledValidModel() throws {
        let fixture = try ModelManagerTestFixtures.makeFixture()
        let manager = ModelManagerTestFixtures.makeManager(fixture: fixture)

        manager.selectModel(id: "tiny")

        XCTAssertNil(manager.selectedModelId)
    }

    func test_modelManager_selectModel_updatesAndPersistsValidModel() throws {
        let fixture = try ModelManagerTestFixtures.makeFixture()
        let directory = try ModelManagerTestFixtures.makeValidDownloadedModelDirectory(base: fixture.modelsDirectory, variant: "tiny")
        let defaults = UserDefaults(suiteName: fixture.suiteName)!
        let firstManager = ModelManagerTestFixtures.makeManager(fixture: fixture, defaults: defaults)

        firstManager.selectModel(id: "tiny")

        XCTAssertEqual(firstManager.selectedModelId, "tiny")
        XCTAssertEqual(try firstManager.resolveInstalledModel(id: "tiny"), directory)

        let secondManager = ModelManagerTestFixtures.makeManager(fixture: fixture, defaults: defaults)
        XCTAssertEqual(secondManager.selectedModelId, "tiny")
    }

    func test_modelManager_refreshModels_discoversOnlyValidDownloadedModels() async throws {
        let fixture = try ModelManagerTestFixtures.makeFixture()
        _ = try ModelManagerTestFixtures.makeValidDownloadedModelDirectory(base: fixture.modelsDirectory, variant: "tiny")
        let incomplete = try ModelManagerTestFixtures.makeIncompleteDownloadedModelDirectory(base: fixture.modelsDirectory, variant: "base.en")
        try Data([1]).write(to: incomplete.appendingPathComponent("AudioEncoder.mlmodelc"))
        let catalog = TestModelCatalog(
            remoteModels: ["openai_whisper-tiny", "openai_whisper-base.en"],
            recommended: ModelSupport(default: "openai_whisper-tiny", supported: ["openai_whisper-tiny"])
        )
        let manager = ModelManagerTestFixtures.makeManager(fixture: fixture, catalog: catalog)

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
    func test_modelManager_downloadModel_validatesAndRefreshesLocalState() async throws {
        let fixture = try ModelManagerTestFixtures.makeFixture()
        let catalog = TestModelCatalog(
            remoteModels: ["openai_whisper-tiny"],
            recommended: ModelSupport(default: "openai_whisper-tiny", supported: ["openai_whisper-tiny"]),
            downloadedVariant: "tiny"
        )
        let manager = ModelManagerTestFixtures.makeManager(fixture: fixture, catalog: catalog)
        try await manager.refreshModels()
        var progressValues: [Double] = []

        try await manager.downloadModel(id: "tiny") { progressValues.append($0) }

        XCTAssertEqual(progressValues, [0.5, 1.0])
        XCTAssertTrue(manager.isModelDownloaded(variantId: "tiny"))
        XCTAssertTrue(manager.availableModels.first?.isDownloaded == true)
        XCTAssertNoThrow(try manager.resolveInstalledModel(id: "tiny"))
    }

    func test_modelManager_importsCustomModelFromSelectedFolder() async throws {
        let fixture = try ModelManagerTestFixtures.makeFixture()
        let source = try ModelManagerTestFixtures.makeCustomModelSource(base: fixture.modelsDirectory)
        let manager = ModelManagerTestFixtures.makeManager(fixture: fixture)

        try await manager.importCustomModel(from: source)

        let installed = try manager.resolveInstalledModel(id: "hinglish")
        XCTAssertEqual(installed.lastPathComponent, "Oriserve_Whisper-Hindi2Hinglish-Prime_889MB")
        XCTAssertTrue(manager.isModelDownloaded(variantId: "hinglish"))
        XCTAssertEqual(manager.whisperKitModelID(for: "hinglish"), "Oriserve_Whisper-Hindi2Hinglish-Prime_889MB")
        XCTAssertEqual(manager.availableModels.first(where: { $0.id == "hinglish" })?.displayName, "Hindi/Hinglish")
    }

    func test_modelManager_importRejectsWrongFolderName() async throws {
        let fixture = try ModelManagerTestFixtures.makeFixture()
        let source = fixture.modelsDirectory.appendingPathComponent("not-a-whisper-model", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let manager = ModelManagerTestFixtures.makeManager(fixture: fixture)

        do {
            try await manager.importCustomModel(from: source)
            XCTFail("Expected invalid custom model directory")
        } catch let error as voiceflow.ModelManager.ModelManagerError {
            XCTAssertEqual(error, .invalidModelDirectory)
        }
    }

    func test_modelManager_deleteModel_blocksActiveModel() throws {
        let fixture = try ModelManagerTestFixtures.makeFixture()
        _ = try ModelManagerTestFixtures.makeValidDownloadedModelDirectory(base: fixture.modelsDirectory, variant: "tiny")
        let manager = ModelManagerTestFixtures.makeManager(fixture: fixture)
        manager.selectModel(id: "tiny")

        XCTAssertThrowsError(try manager.deleteModel(id: "tiny")) { error in
            XCTAssertEqual(error as? voiceflow.ModelManager.ModelManagerError, .cannotDeleteActiveModel)
        }
    }

    func test_modelManager_deleteModel_removesInactiveModel() throws {
        let fixture = try ModelManagerTestFixtures.makeFixture()
        let directory = try ModelManagerTestFixtures.makeValidDownloadedModelDirectory(base: fixture.modelsDirectory, variant: "tiny")
        let manager = ModelManagerTestFixtures.makeManager(fixture: fixture)

        try manager.deleteModel(id: "tiny")

        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertFalse(manager.isModelDownloaded(variantId: "tiny"))
    }

}

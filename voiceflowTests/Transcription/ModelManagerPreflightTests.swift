//
//  ModelManagerPreflightTests.swift
//  VoiceFlowTests
//
//  WhisperKit model discovery and preflight validation behavior.
//

import Foundation
import XCTest
@testable import voiceflow

@MainActor
final class ModelManagerPreflightTests: XCTestCase {
    func test_modelManager_preflightResolvesBaseVariantFromCanonicalDirectory() throws {
        let fixture = try ModelManagerTestFixtures.makeFixture()
        let directory = try ModelManagerTestFixtures.makeValidDownloadedModelDirectory(base: fixture.modelsDirectory, variant: "base")
        let manager = ModelManagerTestFixtures.makeManager(fixture: fixture)

        let report = manager.preflight(modelID: "base")

        XCTAssertTrue(report.isValid, report.diagnosticDescription)
        XCTAssertEqual(report.whisperKitModelFolder, directory)
        XCTAssertEqual(report.validationFailureReason, "none")
    }

    func test_modelManager_resolvesExactlyOneCanonicalDirectory() throws {
        let fixture = try ModelManagerTestFixtures.makeFixture()
        let directory = try ModelManagerTestFixtures.makeValidDownloadedModelDirectory(base: fixture.modelsDirectory, variant: "tiny.en")
        let manager = ModelManagerTestFixtures.makeManager(fixture: fixture)

        let report = manager.preflight(modelID: "tiny.en")

        XCTAssertTrue(report.isValid)
        XCTAssertEqual(report.resolvedModelDirectory, directory)
        XCTAssertEqual(report.whisperKitModelFolder, directory)
        XCTAssertTrue(report.modelDirectoryIsInsideModelsRoot)
        XCTAssertTrue(report.modelDirectoryHasNoSymlink)
        XCTAssertTrue(report.modelIDMatchesDirectory)
    }

    func test_modelManager_preflightDiagnosticsReportEachExpectedComponent() throws {
        let fixture = try ModelManagerTestFixtures.makeFixture()
        let directory = try ModelManagerTestFixtures.makeValidDownloadedModelDirectory(base: fixture.modelsDirectory, variant: "tiny.en")
        let manager = ModelManagerTestFixtures.makeManager(fixture: fixture)

        let report = manager.preflight(modelID: "tiny.en")

        XCTAssertEqual(report.componentDiagnostics.map(\.name), ["MelSpectrogram", "AudioEncoder", "TextDecoder"])
        XCTAssertTrue(report.componentDiagnostics.allSatisfy(\.exists))
        XCTAssertTrue(report.diagnosticDescription.contains("Validation Failure Reason: none"))
        XCTAssertTrue(report.diagnosticDescription.contains(directory.path))
    }

    func test_modelManager_preflightRejectsNestedModelDirectory() throws {
        let fixture = try ModelManagerTestFixtures.makeFixture()
        let directory = try ModelManagerTestFixtures.makeValidDownloadedModelDirectory(base: fixture.modelsDirectory, variant: "tiny.en")
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("openai_whisper-tiny.en", isDirectory: true),
            withIntermediateDirectories: true
        )
        let manager = ModelManagerTestFixtures.makeManager(fixture: fixture)

        let report = manager.preflight(modelID: "tiny.en")

        XCTAssertFalse(report.isValid)
        XCTAssertEqual(report.validationFailureReason, "nested_model_directory")
        XCTAssertEqual(
            report.nestedModelDirectory?.lastPathComponent,
            "openai_whisper-tiny.en"
        )
    }

    func test_modelManager_preflightDescriptionReportsPass() throws {
        let fixture = try ModelManagerTestFixtures.makeFixture()
        _ = try ModelManagerTestFixtures.makeValidDownloadedModelDirectory(base: fixture.modelsDirectory, variant: "tiny.en")
        let manager = ModelManagerTestFixtures.makeManager(fixture: fixture)

        let report = manager.preflight(modelID: "tiny.en")

        XCTAssertTrue(report.diagnosticDescription.contains("RESULT: PASS"))
        XCTAssertTrue(report.diagnosticDescription.contains("WhisperKit Configuration: PASS"))
    }

    func test_modelManager_preflightRejectsMissingModel() throws {
        let fixture = try ModelManagerTestFixtures.makeFixture()
        let manager = ModelManagerTestFixtures.makeManager(fixture: fixture)

        let report = manager.preflight(modelID: "tiny.en")

        XCTAssertFalse(report.isValid)
        XCTAssertFalse(report.modelDirectoryExists)
        XCTAssertNil(report.resolvedModelDirectory)
        XCTAssertThrowsError(try manager.resolveInstalledModel(id: "tiny.en"))
    }

    func test_modelManager_preflightRejectsIncompleteModel() throws {
        let fixture = try ModelManagerTestFixtures.makeFixture()
        let directory = try ModelManagerTestFixtures.makeIncompleteDownloadedModelDirectory(base: fixture.modelsDirectory, variant: "tiny.en")
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("AudioEncoder.mlmodelc"), withIntermediateDirectories: true)
        let manager = ModelManagerTestFixtures.makeManager(fixture: fixture)

        let report = manager.preflight(modelID: "tiny.en")

        XCTAssertFalse(report.isValid)
        XCTAssertTrue(report.modelDirectoryExists)
        XCTAssertFalse(report.expectedModelComponentsPresent)
        XCTAssertEqual(report.validationFailureReason, "required_coreml_component_missing")
        XCTAssertTrue(report.componentDiagnostics.contains {
            $0.name == "TextDecoder" && !$0.exists && !$0.compiledModelExists && !$0.packageExists
        })
    }

}

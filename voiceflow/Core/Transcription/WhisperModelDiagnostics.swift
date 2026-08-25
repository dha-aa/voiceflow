//
//  WhisperModelDiagnostics.swift
//  VoiceFlow
//
//  Structural and load-configuration diagnostics for local WhisperKit models.
//

import Foundation
import WhisperKit

struct WhisperKitComponentDiagnostic: Equatable {
    let name: String
    let compiledModelURL: URL
    let packageURL: URL
    let compiledModelExists: Bool
    let packageExists: Bool

    var exists: Bool {
        compiledModelExists || packageExists
    }
}

struct ModelPreflightReport: Equatable {
    let modelID: String
    let bundleIdentifier: String
    let applicationSupportDirectory: URL
    let modelsRootDirectory: URL
    let resolvedModelDirectory: URL?
    let modelDirectoryExists: Bool
    let modelDirectoryIsReadable: Bool
    let modelDirectoryIsInsideModelsRoot: Bool
    let modelDirectoryHasNoSymlink: Bool
    let modelIDMatchesDirectory: Bool
    let expectedModelComponentsPresent: Bool
    let componentDiagnostics: [WhisperKitComponentDiagnostic]
    let nestedModelDirectory: URL?
    let whisperKitModelFolder: URL?
    let whisperKitConfigurationResolved: Bool

    var isValid: Bool {
        modelDirectoryExists &&
            modelDirectoryIsReadable &&
            modelDirectoryIsInsideModelsRoot &&
            modelDirectoryHasNoSymlink &&
            modelIDMatchesDirectory &&
            expectedModelComponentsPresent &&
            whisperKitConfigurationResolved
    }

    var validationFailureReason: String {
        if !modelDirectoryExists { return "model_directory_missing" }
        if !modelDirectoryIsReadable { return "model_directory_not_readable" }
        if !modelDirectoryIsInsideModelsRoot { return "model_directory_outside_models_root" }
        if !modelDirectoryHasNoSymlink { return "model_directory_symlink" }
        if !modelIDMatchesDirectory { return "model_directory_id_mismatch" }
        if nestedModelDirectory != nil { return "nested_model_directory" }
        if !expectedModelComponentsPresent { return "required_coreml_component_missing" }
        if !whisperKitConfigurationResolved { return "whisperkit_configuration_not_resolved" }
        return "none"
    }

    var diagnosticDescription: String {
        """
        VoiceFlow Model Preflight
        Bundle ID: \(bundleIdentifier)
        Application Support: \(applicationSupportDirectory.path)
        Models Root: \(modelsRootDirectory.path)
        Selected Model: \(modelID)
        Model Directory: \(resolvedModelDirectory?.path ?? "<none>")
        Exists: \(modelDirectoryExists ? "PASS" : "FAIL")
        Readable: \(modelDirectoryIsReadable ? "PASS" : "FAIL")
        Inside Models Root: \(modelDirectoryIsInsideModelsRoot ? "PASS" : "FAIL")
        No Symlink: \(modelDirectoryHasNoSymlink ? "PASS" : "FAIL")
        Model ID: \(modelIDMatchesDirectory ? "PASS" : "FAIL")
        Expected Files: \(expectedModelComponentsPresent ? "PASS" : "FAIL")
        Nested Model Directory: \(nestedModelDirectory?.path ?? "<none>")
        WhisperKit Folder: \(whisperKitModelFolder?.path ?? "<none>")
        WhisperKit Configuration: \(whisperKitConfigurationResolved ? "PASS" : "FAIL")
        Validation Failure Reason: \(validationFailureReason)

        Component Diagnostics:
        \(componentDiagnostics.map { "\($0.name): compiled=\($0.compiledModelExists ? "PASS" : "FAIL"), package=\($0.packageExists ? "PASS" : "FAIL")" }.joined(separator: "\n"))

        RESULT: \(isValid ? "PASS" : "FAIL")
        """
    }
}

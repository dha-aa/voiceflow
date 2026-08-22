//
//  ModelManager.swift
//  VoiceFlow
//
//  Canonical local WhisperKit model storage, validation, and lifecycle management.
//

import Foundation
import Observation
import OSLog
import WhisperKit

struct WhisperModel: Identifiable, Equatable {
    let id: String
    let displayName: String
    let sizeOnDisk: Int64?
    let isDownloaded: Bool
    let isRecommended: Bool
    var isActive: Bool

    init(
        id: String,
        sizeOnDisk: Int64?,
        isDownloaded: Bool,
        isRecommended: Bool,
        isActive: Bool
    ) {
        self.id = id
        self.displayName = Self.makeDisplayName(from: id)
        self.sizeOnDisk = sizeOnDisk
        self.isDownloaded = isDownloaded
        self.isRecommended = isRecommended
        self.isActive = isActive
    }

    private static func makeDisplayName(from id: String) -> String {
        id.replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(whereSeparator: { $0 == " " })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

protocol WhisperKitModelLoadValidator: AnyObject {
    func validateModelLoad(modelID: String, modelFolder: URL, downloadBase: URL) async throws
}

protocol WhisperKitModelCatalog {
    func fetchAvailableModels(from repository: String, matching: [String], downloadBase: URL) async throws -> [String]
    func recommendedRemoteModels(from repository: String, downloadBase: URL) async -> ModelSupport
    func download(
        variant: String,
        from repository: String,
        downloadBase: URL,
        progressCallback: @escaping @Sendable (Progress) -> Void
    ) async throws -> URL
}

private struct LiveWhisperKitModelCatalog: WhisperKitModelCatalog {
    func fetchAvailableModels(from repository: String, matching: [String], downloadBase: URL) async throws -> [String] {
        try await WhisperKit.fetchAvailableModels(
            from: repository,
            matching: matching,
            downloadBase: downloadBase
        )
    }

    func recommendedRemoteModels(from repository: String, downloadBase: URL) async -> ModelSupport {
        await WhisperKit.recommendedRemoteModels(
            from: repository,
            downloadBase: downloadBase
        )
    }

    func download(
        variant: String,
        from repository: String,
        downloadBase: URL,
        progressCallback: @escaping @Sendable (Progress) -> Void
    ) async throws -> URL {
        try await WhisperKit.download(
            variant: variant,
            downloadBase: downloadBase,
            from: repository,
            progressCallback: progressCallback
        )
    }
}

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

@Observable
final class ModelManager {
    static let repository = "argmaxinc/whisperkit-coreml"
    private static let selectedModelDefaultsKey = "selectedWhisperModelId"
    private static let hubModelsDirectory = "models"
    private static let repositoryNamespace = "argmaxinc"
    private static let repositoryName = "whisperkit-coreml"
    private static let modelDirectoryPrefix = "openai_whisper-"

    /// The one application-owned directory used as WhisperKit's download base.
    /// In a sandboxed build, Foundation resolves this Application Support URL
    /// inside the app container.
    static var appModelsDirectory: URL {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            preconditionFailure("VoiceFlow requires an Application Support directory")
        }
        guard let bundleIdentifier = Bundle.main.bundleIdentifier,
              !bundleIdentifier.isEmpty else {
            preconditionFailure("VoiceFlow requires a stable CFBundleIdentifier")
        }

        let directory = applicationSupport
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    /// The repository directory produced by WhisperKit/HubApi for this app-owned download base.
    static var whisperKitModelBase: URL {
        appModelsDirectory
            .appendingPathComponent(hubModelsDirectory, isDirectory: true)
            .appendingPathComponent(repositoryNamespace, isDirectory: true)
            .appendingPathComponent(repositoryName, isDirectory: true)
    }

    private(set) var availableModels: [WhisperModel] = []
    private(set) var selectedModelId: String?
    private(set) var isLoading = false
    var onModelSelectionChanged: ((String) -> Void)?

    private let catalog: WhisperKitModelCatalog
    private let fileManager: FileManager
    private let userDefaults: UserDefaults
    private let modelsDirectory: URL
    weak var modelLoadValidator: WhisperKitModelLoadValidator?

    /// The canonical WhisperKit download base used by catalog and download APIs.
    var downloadBase: URL { modelsDirectory }

    init(
        catalog: WhisperKitModelCatalog = LiveWhisperKitModelCatalog(),
        modelsDirectory: URL = ModelManager.appModelsDirectory,
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        self.catalog = catalog
        self.modelsDirectory = modelsDirectory.standardizedFileURL
        self.userDefaults = userDefaults
        self.fileManager = fileManager
        self.modelLoadValidator = nil
        selectedModelId = userDefaults.string(forKey: Self.selectedModelDefaultsKey)

        try? fileManager.createDirectory(
            at: self.modelsDirectory,
            withIntermediateDirectories: true
        )
    }

    func refreshModels() async throws {
        isLoading = true
        defer { isLoading = false }

        let remoteModelIDs = try await catalog.fetchAvailableModels(
            from: Self.repository,
            matching: ["*"],
            downloadBase: modelsDirectory
        )
        let recommended = await catalog.recommendedRemoteModels(
            from: Self.repository,
            downloadBase: modelsDirectory
        )
        let recommendedIDs = Set(recommended.supported.map(Self.variantID(from:)))

        var models = remoteModelIDs
            .map(Self.variantID(from:))
            .filter { !$0.isEmpty }
            .map { variantID in
                let report = preflight(modelID: variantID)
                if report.isValid, let directory = report.resolvedModelDirectory {
                    VoiceFlowLog.model.info("model_detected model_id=\(variantID, privacy: .public) model_directory=\(directory.path, privacy: .public) source=refresh")
                }
                return WhisperModel(
                    id: variantID,
                    sizeOnDisk: report.isValid ? report.resolvedModelDirectory.flatMap(directorySize) : nil,
                    isDownloaded: report.isValid,
                    isRecommended: recommendedIDs.contains(variantID),
                    isActive: selectedModelId == variantID && report.isValid
                )
            }

        var seen = Set<String>()
        models = models.filter { seen.insert($0.id).inserted }
        availableModels = models.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }

        if let selectedModelId,
           !availableModels.contains(where: { $0.id == selectedModelId && $0.isDownloaded }) {
            self.selectedModelId = nil
            userDefaults.removeObject(forKey: Self.selectedModelDefaultsKey)
            VoiceFlowLog.model.info("model_selection_cleared reason=model_not_installed")
        }
    }

    /// Selects an installed, preflight-valid model and persists it in the app's
    /// standard container defaults domain. Invalid or non-installed models are
    /// rejected without changing the current selection.
    func selectModel(id: String) {
        let normalizedID = Self.variantID(from: id)
        guard !normalizedID.isEmpty else {
            VoiceFlowLog.model.error("model_selection_rejected reason=invalid_model_identifier")
            return
        }
        let report = preflight(modelID: normalizedID)
        guard report.isValid else {
            VoiceFlowLog.model.error("model_selection_rejected model_id=\(normalizedID, privacy: .public) reason=preflight_failed")
            return
        }

        let previousModelID = selectedModelId
        selectedModelId = normalizedID
        userDefaults.set(normalizedID, forKey: Self.selectedModelDefaultsKey)
        availableModels = availableModels.map { model in
            var updated = model
            updated.isActive = model.id == normalizedID
            return updated
        }
        VoiceFlowLog.model.info("model_selected model_id=\(normalizedID, privacy: .public)")
        if previousModelID != normalizedID {
            onModelSelectionChanged?(normalizedID)
        }
    }

    /// Downloads a model into the canonical WhisperKit cache and only reports
    /// it as installed after validating the exact directory returned by the SDK.
    func downloadModel(
        id: String,
        progress: @escaping (Double) -> Void
    ) async throws {
        let variantID = Self.variantID(from: id)
        guard !variantID.isEmpty else { throw ModelManagerError.invalidModelIdentifier }

        isLoading = true
        defer { isLoading = false }
        VoiceFlowLog.model.info("model_download_started model_id=\(variantID, privacy: .public) download_base=\(self.modelsDirectory.path, privacy: .public)")

        let downloadedDirectory = try await catalog.download(
            variant: variantID,
            from: Self.repository,
            downloadBase: modelsDirectory,
            progressCallback: { update in
                progress(min(max(update.fractionCompleted, 0), 1))
            }
        )

        VoiceFlowLog.model.info("model_download_completed model_id=\(variantID, privacy: .public) downloaded_path=\(downloadedDirectory.standardizedFileURL.path, privacy: .public)")
        guard let report = preflight(downloadedDirectory: downloadedDirectory, modelID: variantID) else {
            VoiceFlowLog.model.error("model_download_validation_failed model_id=\(variantID, privacy: .public) downloaded_path=\(downloadedDirectory.standardizedFileURL.path, privacy: .public) reason=path_outside_models_root")
            throw ModelManagerError.invalidModelDirectory
        }
        guard report.isValid, let validatedDirectory = report.resolvedModelDirectory else {
            if isSafeToRemoveDownloadedArtifact(downloadedDirectory) {
                try? fileManager.removeItem(at: downloadedDirectory)
                VoiceFlowLog.model.info("model_download_artifact_removed model_id=\(variantID, privacy: .public) reason=validation_failed")
            }
            VoiceFlowLog.model.error("model_download_validation_failed model_id=\(variantID, privacy: .public) downloaded_path=\(downloadedDirectory.standardizedFileURL.path, privacy: .public)")
            throw ModelManagerError.invalidModelDirectory
        }

        if let modelLoadValidator {
            VoiceFlowLog.model.info("model_download_load_validation_started model_id=\(variantID, privacy: .public) model_folder=\(validatedDirectory.path, privacy: .public)")
            do {
                try await modelLoadValidator.validateModelLoad(
                    modelID: variantID,
                    modelFolder: validatedDirectory,
                    downloadBase: modelsDirectory
                )
                VoiceFlowLog.model.info("model_download_load_validation_succeeded model_id=\(variantID, privacy: .public) model_folder=\(validatedDirectory.path, privacy: .public)")
            } catch {
                VoiceFlowLog.model.error("model_download_load_validation_failed model_id=\(variantID, privacy: .public) model_folder=\(validatedDirectory.path, privacy: .public) error=\(String(describing: error), privacy: .public)")
                try? fileManager.removeItem(at: validatedDirectory)
                throw ModelManagerError.modelLoadFailed
            }
        }

        refreshLocalModelState(for: variantID)
        if let detectedDirectory = report.resolvedModelDirectory {
            VoiceFlowLog.model.info("model_download_validated model_id=\(variantID, privacy: .public) validated_path=\(detectedDirectory.path, privacy: .public)")
        }
    }

    /// Deletes all installed snapshot directories for an inactive model and
    /// verifies that no matching model directory remains.
    func deleteModel(id: String) throws {
        let variantID = Self.variantID(from: id)
        if selectedModelId == variantID {
            throw ModelManagerError.cannotDeleteActiveModel
        }

        let directories = modelDirectories(for: variantID)
        guard !directories.isEmpty else {
            throw ModelManagerError.modelNotDownloaded
        }

        for directory in directories {
            try fileManager.removeItem(at: directory)
            VoiceFlowLog.model.info("model_deleted model_id=\(variantID, privacy: .public)")
        }

        guard modelDirectories(for: variantID).isEmpty else {
            throw ModelManagerError.deleteVerificationFailed
        }
        refreshLocalModelState(for: variantID)
    }

    /// Returns true only when exactly one local model directory satisfies the
    /// same preflight contract used by transcription.
    func isModelDownloaded(variantId: String) -> Bool {
        preflight(modelID: Self.variantID(from: variantId)).isValid
    }

    /// Resolves the exact model directory that should be passed to
    /// `WhisperKitConfig.modelFolder`.
    func resolveInstalledModel(id: String) throws -> URL {
        let normalizedID = Self.variantID(from: id)
        guard !normalizedID.isEmpty else { throw ModelManagerError.invalidModelIdentifier }
        let candidates = modelDirectories(for: normalizedID)
        guard candidates.count == 1 else {
            throw ModelManagerError.modelNotDownloaded
        }
        let report = preflight(modelID: normalizedID)
        guard report.isValid, let directory = report.resolvedModelDirectory else {
            throw ModelManagerError.invalidModelDirectory
        }
        return directory
    }

    /// Produces the same preflight report used by model discovery and
    /// transcription, making it suitable for a development diagnostic command.
    func preflightSelectedModel() -> ModelPreflightReport? {
        guard let selectedModelId else { return nil }
        return preflight(modelID: selectedModelId)
    }

    func preflight(modelID: String) -> ModelPreflightReport {
        let normalizedID = Self.variantID(from: modelID)
        let candidates = modelDirectories(for: normalizedID)
        let candidate = candidates.count == 1 ? candidates[0] : nil
        let report = makePreflightReport(modelID: normalizedID, directory: candidate)
        log(report: report)
        return report
    }

    private func refreshLocalModelState(for variantID: String) {
        let report = preflight(modelID: variantID)
        guard report.isValid else { return }

        if let index = availableModels.firstIndex(where: { $0.id == variantID }) {
            let existing = availableModels[index]
            availableModels[index] = WhisperModel(
                id: variantID,
                sizeOnDisk: report.resolvedModelDirectory.flatMap(directorySize),
                isDownloaded: true,
                isRecommended: existing.isRecommended,
                isActive: existing.isActive
            )
        } else {
            availableModels.append(
                WhisperModel(
                    id: variantID,
                    sizeOnDisk: report.resolvedModelDirectory.flatMap(directorySize),
                    isDownloaded: true,
                    isRecommended: false,
                    isActive: selectedModelId == variantID
                )
            )
            availableModels.sort { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
        }

        if let directory = report.resolvedModelDirectory {
            VoiceFlowLog.model.info("model_detected model_id=\(variantID, privacy: .public) model_directory=\(directory.path, privacy: .public) source=download")
        }
    }

    private func localModelDirectory(for variantID: String) -> URL? {
        let candidates = modelDirectories(for: variantID)
        guard candidates.count == 1 else { return nil }
        return candidates[0]
    }

    private func modelDirectories(for variantID: String) -> [URL] {
        guard !variantID.isEmpty else { return [] }
        let repositoryDirectory = modelsDirectory
            .appendingPathComponent(Self.hubModelsDirectory, isDirectory: true)
            .appendingPathComponent(Self.repositoryNamespace, isDirectory: true)
            .appendingPathComponent(Self.repositoryName, isDirectory: true)
        guard let repositoryModels = try? fileManager.contentsOfDirectory(
            at: repositoryDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let modelDirectoryName = "\(Self.modelDirectoryPrefix)\(variantID)"
        return repositoryModels
            .filter { $0.lastPathComponent == modelDirectoryName }
            .filter { url in
                guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey]),
                      values.isDirectory == true else { return false }
                return fileManager.fileExists(atPath: url.path)
            }
    }

    private func isSafeToRemoveDownloadedArtifact(_ directory: URL) -> Bool {
        let standardized = directory.standardizedFileURL
        return standardized.path.hasPrefix(modelsDirectory.path + "/") &&
            standardized.lastPathComponent.hasPrefix(Self.modelDirectoryPrefix)
    }

    private func preflight(downloadedDirectory: URL, modelID: String) -> ModelPreflightReport? {
        guard downloadedDirectory.standardizedFileURL.path.hasPrefix(modelsDirectory.path + "/") else {
            return nil
        }
        let report = makePreflightReport(modelID: modelID, directory: downloadedDirectory)
        log(report: report)
        return report
    }

    private func makePreflightReport(modelID: String, directory: URL?) -> ModelPreflightReport {
        let resolvedDirectory = directory?.standardizedFileURL
        let exists = resolvedDirectory.map { fileManager.fileExists(atPath: $0.path) } ?? false
        let isDirectory = resolvedDirectory.flatMap {
            try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory
        } == true
        let readable = exists && isDirectory && fileManager.isReadableFile(atPath: resolvedDirectory!.path)
        let insideRoot = resolvedDirectory.map { isInsideModelsRoot($0) } ?? false
        let noSymlink = resolvedDirectory.map { directory in
            (try? directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true
        } ?? false
        let idMatches = resolvedDirectory?.lastPathComponent == "\(Self.modelDirectoryPrefix)\(modelID)"
        let componentDiagnostics = resolvedDirectory.map(componentDiagnostics(in:)) ?? []
        let components = exists && isDirectory && componentDiagnostics.allSatisfy(\.exists)
        let nestedDirectory = resolvedDirectory.flatMap { nestedModelDirectory(in: $0, modelID: modelID) }
        let config = resolvedDirectory.flatMap { folder -> WhisperKitConfig? in
            guard components else { return nil }
            return WhisperKitConfig(
                model: modelID,
                modelFolder: folder.path,
                load: false,
                download: false
            )
        }
        let configFolder = config?.modelFolder.map(URL.init(fileURLWithPath:))
        let configPath = configFolder?.standardizedFileURL.path
        let resolvedPath = resolvedDirectory?.standardizedFileURL.path
        let configResolved = configPath != nil && configPath == resolvedPath

        return ModelPreflightReport(
            modelID: modelID,
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "<missing>",
            applicationSupportDirectory: modelsDirectory.deletingLastPathComponent(),
            modelsRootDirectory: modelsDirectory,
            resolvedModelDirectory: resolvedDirectory,
            modelDirectoryExists: exists && isDirectory,
            modelDirectoryIsReadable: readable,
            modelDirectoryIsInsideModelsRoot: insideRoot,
            modelDirectoryHasNoSymlink: noSymlink,
            modelIDMatchesDirectory: idMatches,
            expectedModelComponentsPresent: components && nestedDirectory == nil,
            componentDiagnostics: componentDiagnostics,
            nestedModelDirectory: nestedDirectory,
            whisperKitModelFolder: configFolder,
            whisperKitConfigurationResolved: configResolved
        )
    }

    private func log(report: ModelPreflightReport) {
        let resolved = report.resolvedModelDirectory?.path ?? "<none>"
        let whisperKitFolder = report.whisperKitModelFolder?.path ?? "<none>"
        VoiceFlowLog.model.info(
            "model_preflight_started model_id=\(report.modelID, privacy: .public) bundle_identifier=\(report.bundleIdentifier, privacy: .public) application_support_directory=\(report.applicationSupportDirectory.path, privacy: .public) models_root_directory=\(report.modelsRootDirectory.path, privacy: .public)"
        )
        VoiceFlowLog.model.info(
            "model_directory_resolved model_id=\(report.modelID, privacy: .public) resolved_model_directory=\(resolved, privacy: .public) model_directory_exists=\(report.modelDirectoryExists, privacy: .public) model_directory_readable=\(report.modelDirectoryIsReadable, privacy: .public) inside_models_root=\(report.modelDirectoryIsInsideModelsRoot, privacy: .public) no_symlink=\(report.modelDirectoryHasNoSymlink, privacy: .public) id_matches=\(report.modelIDMatchesDirectory, privacy: .public) expected_components=\(report.expectedModelComponentsPresent, privacy: .public) nested_model_directory=\(report.nestedModelDirectory?.path ?? "<none>", privacy: .public) whisperkit_model_folder=\(whisperKitFolder, privacy: .public) validation_result=\(report.isValid ? "pass" : "fail", privacy: .public) validation_failure_reason=\(report.validationFailureReason, privacy: .public)"
        )
        for component in report.componentDiagnostics {
            VoiceFlowLog.model.info(
                "model_expected_component model_id=\(report.modelID, privacy: .public) component=\(component.name, privacy: .public) expected_file=\(component.compiledModelURL.path, privacy: .public) expected_file_exists=\(component.compiledModelExists, privacy: .public) expected_directory=\(component.packageURL.path, privacy: .public) expected_directory_exists=\(component.packageExists, privacy: .public)"
            )
        }
        if report.isValid {
            VoiceFlowLog.model.info("model_preflight_succeeded model_id=\(report.modelID, privacy: .public) validation_result=pass")
        } else {
            VoiceFlowLog.model.error("model_preflight_failed model_id=\(report.modelID, privacy: .public) validation_result=fail validation_failure_reason=\(report.validationFailureReason, privacy: .public)")
        }
    }

    private func componentDiagnostics(in directory: URL) -> [WhisperKitComponentDiagnostic] {
        ["MelSpectrogram", "AudioEncoder", "TextDecoder"].map { name in
            let compiled = directory.appendingPathComponent("\(name).mlmodelc")
            let package = directory.appendingPathComponent("\(name).mlpackage")
            return WhisperKitComponentDiagnostic(
                name: name,
                compiledModelURL: compiled,
                packageURL: package,
                compiledModelExists: fileManager.fileExists(atPath: compiled.path),
                packageExists: fileManager.fileExists(atPath: package.path)
            )
        }
    }

    private func nestedModelDirectory(in directory: URL, modelID: String) -> URL? {
        let nested = directory.appendingPathComponent("\(Self.modelDirectoryPrefix)\(modelID)", isDirectory: true)
        guard fileManager.fileExists(atPath: nested.path),
              (try? nested.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            return nil
        }
        return nested
    }

    private func isInsideModelsRoot(_ directory: URL) -> Bool {
        let rootPath = modelsDirectory.standardizedFileURL.path
        let directoryPath = directory.standardizedFileURL.path
        return directoryPath.hasPrefix(rootPath + "/")
    }

    private func directorySize(_ directory: URL) -> Int64? {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey]
            ), values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    private static func variantID(from remoteID: String) -> String {
        let firstPathComponent = remoteID.split(separator: "/").first.map(String.init) ?? remoteID
        return firstPathComponent.replacingOccurrences(of: modelDirectoryPrefix, with: "")
    }

    enum ModelManagerError: Error, Equatable {
        case invalidModelIdentifier
        case modelNotDownloaded
        case invalidModelDirectory
        case modelLoadFailed
        case cannotDeleteActiveModel
        case deleteVerificationFailed
    }
}

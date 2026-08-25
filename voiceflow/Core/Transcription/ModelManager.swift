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
    nonisolated static var appModelsDirectory: URL {
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
    private(set) var isRefreshing = false
    var onModelSelectionChanged: ((String) -> Void)?

    private let catalog: WhisperKitModelCatalog
    private let fileManager: FileManager
    private let userDefaults: UserDefaults
    private let modelsDirectory: URL
    weak var modelLoadValidator: WhisperKitModelLoadValidator?

    /// The canonical WhisperKit download base used by catalog and download APIs.
    var downloadBase: URL { modelsDirectory }

    /// Returns the model identity expected by WhisperKit for a VoiceFlow model ID.
    func whisperKitModelID(for id: String) -> String {
        let normalizedID = Self.variantID(from: id)
        return WhisperModelDefinition.customModels.first {
            $0.id == normalizedID ||
                $0.remoteModelID == normalizedID ||
                $0.folderName == normalizedID
        }?.remoteModelID ?? normalizedID
    }

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
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

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

        for definition in WhisperModelDefinition.customModels {
            let report = preflight(modelID: definition.id)
            guard report.isValid else { continue }
            if let directory = report.resolvedModelDirectory {
                VoiceFlowLog.model.info("model_detected model_id=\(definition.id, privacy: .public) model_directory=\(directory.path, privacy: .public) source=custom_import")
            }
            models.append(
                WhisperModel(
                    id: definition.id,
                    displayName: definition.displayName,
                    sizeOnDisk: report.resolvedModelDirectory.flatMap(directorySize),
                    isDownloaded: true,
                    isRecommended: definition.isRecommended,
                    isActive: selectedModelId == definition.id
                )
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

    /// Imports the registered custom Core ML model from a user-selected folder.
    /// The source is copied into the repository-aware managed directory only
    /// after structural and real WhisperKit load validation succeed.
    func importCustomModel(from sourceDirectory: URL) async throws {
        guard let definition = WhisperModelDefinition.customModels.first else {
            throw ModelManagerError.invalidModelIdentifier
        }
        let source = sourceDirectory.standardizedFileURL
        let sourceValues = try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard sourceValues.isDirectory == true,
              sourceValues.isSymbolicLink != true,
              source.lastPathComponent == definition.folderName else {
            VoiceFlowLog.model.error("model_import_rejected reason=source_folder_invalid")
            throw ModelManagerError.invalidModelDirectory
        }

        let destination = modelDirectory(for: definition.id)
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw ModelManagerError.modelAlreadyInstalled
        }

        let repositoryRoot = repositoryDirectory(for: definition.id)
        let stagingRoot = repositoryRoot.appendingPathComponent(".voiceflow-import-\(UUID().uuidString)", isDirectory: true)
        let stagedModel = stagingRoot.appendingPathComponent(definition.folderName, isDirectory: true)
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingRoot) }

        VoiceFlowLog.model.info("model_import_started model_id=\(definition.id, privacy: .public) source_directory=\(source.path, privacy: .public)")
        do {
            try fileManager.copyItem(at: source, to: stagedModel)
            let report = makePreflightReport(modelID: definition.id, directory: stagedModel)
            log(report: report)
            guard report.isValid else {
                throw ModelManagerError.invalidModelDirectory
            }

            if let modelLoadValidator {
                try await modelLoadValidator.validateModelLoad(
                    modelID: definition.remoteModelID,
                    modelFolder: stagedModel,
                    downloadBase: modelsDirectory
                )
            }

            try fileManager.createDirectory(at: repositoryRoot, withIntermediateDirectories: true)
            try fileManager.moveItem(at: stagedModel, to: destination)
            refreshLocalModelState(for: definition.id)
            VoiceFlowLog.model.info("model_import_succeeded model_id=\(definition.id, privacy: .public) managed_directory=\(destination.path, privacy: .public)")
        } catch let error as ModelManagerError {
            VoiceFlowLog.model.error("model_import_failed model_id=\(definition.id, privacy: .public) category=\(String(describing: error), privacy: .public)")
            throw error
        } catch {
            VoiceFlowLog.model.error("model_import_failed model_id=\(definition.id, privacy: .public) category=runtime error=\(String(describing: error), privacy: .public)")
            throw ModelManagerError.invalidModelDirectory
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
                displayName: WhisperModelDefinition.customModels.first(where: { $0.id == variantID })?.displayName,
                sizeOnDisk: report.resolvedModelDirectory.flatMap(directorySize),
                isDownloaded: true,
                isRecommended: existing.isRecommended,
                isActive: existing.isActive
            )
        } else {
            availableModels.append(
                WhisperModel(
                    id: variantID,
                    displayName: WhisperModelDefinition.customModels.first(where: { $0.id == variantID })?.displayName,
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
        let repositoryDirectory = repositoryDirectory(for: variantID)
        guard let repositoryModels = try? fileManager.contentsOfDirectory(
            at: repositoryDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let modelDirectoryName = expectedFolderName(for: variantID)
        return repositoryModels
            .filter { $0.lastPathComponent == modelDirectoryName }
            .filter { url in
                guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey]),
                      values.isDirectory == true else { return false }
                return fileManager.fileExists(atPath: url.path)
            }
    }

    private func repositoryDirectory(for modelID: String) -> URL {
        if let definition = WhisperModelDefinition.customModels.first(where: {
            $0.id == modelID || $0.remoteModelID == modelID || $0.folderName == modelID
        }) {
            let parts = definition.repository.split(separator: "/")
            let namespace = parts.first.map(String.init) ?? ""
            let repository = parts.dropFirst().first.map(String.init) ?? ""
            return modelsDirectory
                .appendingPathComponent(Self.hubModelsDirectory, isDirectory: true)
                .appendingPathComponent(namespace, isDirectory: true)
                .appendingPathComponent(repository, isDirectory: true)
        }

        return modelsDirectory
            .appendingPathComponent(Self.hubModelsDirectory, isDirectory: true)
            .appendingPathComponent(Self.repositoryNamespace, isDirectory: true)
            .appendingPathComponent(Self.repositoryName, isDirectory: true)
    }

    private func expectedFolderName(for modelID: String) -> String {
        if let definition = WhisperModelDefinition.customModels.first(where: {
            $0.id == modelID || $0.remoteModelID == modelID || $0.folderName == modelID
        }) {
            return definition.folderName
        }
        return "\(Self.modelDirectoryPrefix)\(modelID)"
    }

    private func modelDirectory(for modelID: String) -> URL {
        repositoryDirectory(for: modelID)
            .appendingPathComponent(expectedFolderName(for: modelID), isDirectory: true)
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
        let idMatches = resolvedDirectory?.lastPathComponent == expectedFolderName(for: modelID)
        let componentDiagnostics = resolvedDirectory.map(componentDiagnostics(in:)) ?? []
        let components = exists && isDirectory && componentDiagnostics.allSatisfy(\.exists)
        let nestedDirectory = resolvedDirectory.flatMap { nestedModelDirectory(in: $0, modelID: modelID) }
        let config = resolvedDirectory.flatMap { folder -> WhisperKitConfig? in
            guard components else { return nil }
            return WhisperKitConfig(
                model: whisperKitModelID(for: modelID),
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
        let nested = directory.appendingPathComponent(expectedFolderName(for: modelID), isDirectory: true)
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
        case modelAlreadyInstalled
        case modelNotDownloaded
        case invalidModelDirectory
        case modelLoadFailed
        case cannotDeleteActiveModel
        case deleteVerificationFailed
    }
}

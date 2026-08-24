//
//  ParakeetModelManager.swift
//  VoiceFlow
//
//  Local FluidAudio Parakeet TDT model lifecycle.
//

import CoreML
import FluidAudio
import Foundation
import Observation
import OSLog

/// Parakeet models that VoiceFlow can load through FluidAudio.
///
/// The NVIDIA repositories are the upstream NeMo/Transformers sources. VoiceFlow
/// downloads the corresponding FluidInference Core ML conversions instead.
enum ParakeetModelVariant: String, CaseIterable, Identifiable, Hashable, Sendable {
    case v3
    case v2

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .v3: "Parakeet TDT 0.6B v3"
        case .v2: "Parakeet TDT 0.6B v2"
        }
    }

    var languageDescription: String {
        switch self {
        case .v3: "Multilingual · 25 European languages"
        case .v2: "English"
        }
    }

    var repository: String {
        switch self {
        case .v3: "FluidInference/parakeet-tdt-0.6b-v3-coreml"
        case .v2: "FluidInference/parakeet-tdt-0.6b-v2-coreml"
        }
    }

    var upstreamRepository: String {
        switch self {
        case .v3: "nvidia/parakeet-tdt-0.6b-v3"
        case .v2: "nvidia/parakeet-tdt-0.6b-v2"
        }
    }

    /// FluidAudio strips `-coreml` from these repository names for its cache.
    var cacheDirectoryName: String {
        switch self {
        case .v3: "parakeet-tdt-0.6b-v3"
        case .v2: "parakeet-tdt-0.6b-v2"
        }
    }

    var asrVersion: AsrModelVersion {
        switch self {
        case .v3: .v3
        case .v2: .v2
        }
    }

    /// v3 uses the int8 encoder; v2 has a single `Encoder.mlmodelc` artifact.
    var encoderPrecision: ParakeetEncoderPrecision { .int8 }
}

struct ParakeetModelValidation: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case notInstalled
        case complete
        case missingArtifacts([String])
        case invalidCoreMLArtifacts([String])
        case incomplete(missingArtifacts: [String], invalidCoreMLArtifacts: [String])
        case unsupportedSourceFormat([String])
    }

    let status: Status

    var isComplete: Bool {
        if case .complete = status { return true }
        return false
    }

    var isPresent: Bool {
        if case .notInstalled = status { return false }
        return true
    }

    nonisolated var message: String {
        switch status {
        case .notInstalled:
            "Not installed. Download the FluidAudio Core ML conversion."
        case .complete:
            "Complete FluidAudio Core ML bundle"
        case .missingArtifacts(let artifacts):
            "Incomplete model. Missing: \(artifacts.joined(separator: ", "))."
        case .invalidCoreMLArtifacts(let artifacts):
            "Incomplete Core ML bundle: \(artifacts.joined(separator: "; "))."
        case .incomplete(let missingArtifacts, let invalidCoreMLArtifacts):
            "Incomplete model. Missing: \(missingArtifacts.joined(separator: ", ")). Core ML issues: \(invalidCoreMLArtifacts.joined(separator: "; "))."
        case .unsupportedSourceFormat(let markers):
            "This is an NVIDIA NeMo/Transformers source repository (\(markers.joined(separator: ", "))), not a FluidAudio Core ML bundle. Download the FluidInference conversion instead."
        }
    }
}

@MainActor
protocol ParakeetModelProviding: AnyObject {
    var isInstalled: Bool { get }
    var isSupportedPlatform: Bool { get }
    var modelDirectory: URL { get }
    var selectedVariant: ParakeetModelVariant { get }
}

typealias ParakeetDownloadOperation = @Sendable (
    URL,
    Bool,
    AsrModelVersion,
    ParakeetEncoderPrecision,
    @escaping @Sendable (DownloadProgress) -> Void
) async throws -> URL

@MainActor
@Observable
final class ParakeetModelManager: ParakeetModelProviding {
    static let modelBaseDirectory: URL = ModelManager.appModelsDirectory
        .appendingPathComponent("fluidaudio", isDirectory: true)

    private static let selectedVariantKey = "selectedParakeetModelVariant"
    private static let compiledBundleContents = ["model.mil", "metadata.json", "coremldata.bin"]

    private let fileManager: FileManager
    private let userDefaults: UserDefaults
    private(set) var selectedVariant: ParakeetModelVariant
    private(set) var isInstalled: Bool
    private(set) var isLoading = false
    private(set) var progress = 0.0
    private(set) var validation: ParakeetModelValidation
    private(set) var errorMessage: String?
    private(set) var isCancelling = false
    private var downloadTask: Task<Void, Never>?
    private var operationID = 0
    private let downloadOperation: ParakeetDownloadOperation
    var onVariantChanged: (() -> Void)?

    init(
        fileManager: FileManager = .default,
        userDefaults: UserDefaults = .standard,
        downloadOperation: @escaping ParakeetDownloadOperation = { directory, force, version, precision, progressHandler in
            try await AsrModels.download(
                to: directory,
                force: force,
                version: version,
                encoderPrecision: precision,
                progressHandler: progressHandler
            )
        }
    ) {
        self.fileManager = fileManager
        self.userDefaults = userDefaults
        self.downloadOperation = downloadOperation
        let rawVariant = userDefaults.string(forKey: Self.selectedVariantKey)
        let variant = ParakeetModelVariant(rawValue: rawVariant ?? "") ?? .v3
        self.selectedVariant = variant
        let initialValidation = Self.validation(
            at: Self.modelDirectory(for: variant),
            variant: variant,
            fileManager: fileManager
        )
        self.validation = initialValidation
        self.isInstalled = initialValidation.isComplete
    }

    var modelDirectory: URL {
        Self.modelDirectory(for: selectedVariant)
    }

    var isSupportedPlatform: Bool {
        #if arch(arm64)
        true
        #else
        false
        #endif
    }

    var needsRepair: Bool {
        validation.isPresent && !validation.isComplete
    }

    func selectVariant(_ variant: ParakeetModelVariant) {
        guard selectedVariant != variant else { return }
        selectedVariant = variant
        userDefaults.set(variant.rawValue, forKey: Self.selectedVariantKey)
        refresh()
        VoiceFlowLog.model.info(
            "parakeet_variant_selected variant=\(variant.rawValue, privacy: .public) repository=\(variant.repository, privacy: .public)"
        )
        onVariantChanged?()
    }

    func refresh() {
        validation = Self.validation(
            at: modelDirectory,
            variant: selectedVariant,
            fileManager: fileManager
        )
        isInstalled = validation.isComplete
    }

    func startDownload(force: Bool = false) {
        guard !isLoading else { return }
        operationID += 1
        let operation = operationID
        errorMessage = nil
        isCancelling = false
        downloadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.download(force: force) { [weak self] value in
                    guard let self, self.operationID == operation else { return }
                    self.progress = value
                }
                guard self.operationID == operation else { return }
                self.errorMessage = nil
            } catch is CancellationError {
                guard self.operationID == operation else { return }
                self.refresh()
            } catch {
                guard self.operationID == operation else { return }
                self.refresh()
                self.errorMessage = error.localizedDescription
            }
            guard self.operationID == operation else { return }
            self.isCancelling = false
            self.downloadTask = nil
        }
    }

    func repair() throws {
        guard !isLoading else { return }
        _ = try Self.repairModel(at: modelDirectory, fileManager: fileManager)
        refresh()
        errorMessage = nil
    }

    static func repairModel(
        at directory: URL,
        fileManager: FileManager = .default
    ) throws -> Bool {
        guard fileManager.fileExists(atPath: directory.path) else { return false }
        try fileManager.removeItem(at: directory)
        return true
    }

    func cancelDownload() {
        guard isLoading, !isCancelling else { return }
        isCancelling = true
        downloadTask?.cancel()
    }

    func dismissError() {
        errorMessage = nil
    }

    func download(
        force: Bool = false,
        progress progressHandler: @escaping @MainActor (Double) -> Void
    ) async throws {
        guard isSupportedPlatform else {
            throw ParakeetModelError.unsupportedPlatform
        }

        let variant = selectedVariant
        let directory = Self.modelDirectory(for: variant)
        isLoading = true
        progress = 0
        isInstalled = false
        defer { isLoading = false }

        VoiceFlowLog.model.info(
            "parakeet_model_download_started variant=\(variant.rawValue, privacy: .public) repository=\(variant.repository, privacy: .public) model_directory=\(directory.path, privacy: .public) force=\(force, privacy: .public)"
        )

        do {
            try Task.checkCancellation()
            _ = try await downloadOperation(
                directory,
                force,
                variant.asrVersion,
                variant.encoderPrecision,
                { update in
                    Task { @MainActor in
                        self.progress = min(max(update.fractionCompleted, 0), 1)
                        progressHandler(self.progress)
                    }
                }
            )

            try Task.checkCancellation()
            let structuralValidation = Self.validation(
                at: directory,
                variant: variant,
                fileManager: fileManager
            )
            validation = structuralValidation
            guard structuralValidation.isComplete else {
                VoiceFlowLog.model.error(
                    "parakeet_model_validation_failed variant=\(variant.rawValue, privacy: .public) status=\(structuralValidation.message, privacy: .public)"
                )
                throw ParakeetModelError.invalidModel(structuralValidation)
            }

            // Structural checks catch partial downloads. FluidAudio loading catches
            // malformed compiled bundles before the UI reports the model as installed.
            do {
                _ = try await AsrModels.load(
                    from: directory,
                    version: variant.asrVersion,
                    encoderPrecision: variant.encoderPrecision
                )
            } catch {
                let loadError = ParakeetModelError.loadFailed(underlying: error)
                VoiceFlowLog.model.error(
                    "parakeet_model_validation_failed variant=\(variant.rawValue, privacy: .public) reason=load_failed error=\(String(describing: error), privacy: .public)"
                )
                throw loadError
            }

            validation = ParakeetModelValidation(status: .complete)
            isInstalled = true
            progress = 1
            progressHandler(1)
            VoiceFlowLog.model.info(
                "parakeet_model_download_validated variant=\(variant.rawValue, privacy: .public) model_directory=\(directory.path, privacy: .public)"
            )
        } catch {
            isInstalled = false
            if Task.isCancelled {
                refresh()
                throw CancellationError()
            }
            if !(error is ParakeetModelError) {
                validation = Self.validation(at: directory, variant: variant, fileManager: fileManager)
            }
            VoiceFlowLog.model.error(
                "parakeet_model_download_failed variant=\(variant.rawValue, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
            throw error
        }
    }

    func delete() throws {
        guard fileManager.fileExists(atPath: modelDirectory.path) else {
            throw ParakeetModelError.notInstalled
        }
        try fileManager.removeItem(at: modelDirectory)
        refresh()
        VoiceFlowLog.model.info(
            "parakeet_model_deleted variant=\(self.selectedVariant.rawValue, privacy: .public) model_directory=\(self.modelDirectory.path, privacy: .public)"
        )
    }

    static func modelDirectory(for variant: ParakeetModelVariant) -> URL {
        modelBaseDirectory.appendingPathComponent(variant.cacheDirectoryName, isDirectory: true)
    }

    static func validation(
        at directory: URL,
        variant: ParakeetModelVariant,
        fileManager: FileManager = .default
    ) -> ParakeetModelValidation {
        guard fileManager.fileExists(atPath: directory.path) else {
            return ParakeetModelValidation(status: .notInstalled)
        }

        let sourceMarkers = rawNVIDIARepositoryMarkers(at: directory, fileManager: fileManager)
        if !sourceMarkers.isEmpty {
            return ParakeetModelValidation(status: .unsupportedSourceFormat(sourceMarkers))
        }

        let requiredArtifacts = requiredArtifacts(for: variant)
        let missingArtifacts = requiredArtifacts.filter {
            !fileManager.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
        var invalidBundles: [String] = []
        for artifact in requiredArtifacts where artifact.hasSuffix(".mlmodelc") {
            let bundleURL = directory.appendingPathComponent(artifact)
            guard fileManager.fileExists(atPath: bundleURL.path) else { continue }
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: bundleURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                invalidBundles.append("\(artifact) is not a compiled model directory")
                continue
            }
            let missingContents = Self.compiledBundleContents.filter {
                !fileManager.fileExists(atPath: bundleURL.appendingPathComponent($0).path)
            }
            if !missingContents.isEmpty {
                invalidBundles.append("\(artifact) missing \(missingContents.joined(separator: ", "))")
            }
        }

        let sortedMissingArtifacts = missingArtifacts.sorted()
        let sortedInvalidBundles = invalidBundles.sorted()
        if !sortedMissingArtifacts.isEmpty && !sortedInvalidBundles.isEmpty {
            return ParakeetModelValidation(status: .incomplete(
                missingArtifacts: sortedMissingArtifacts,
                invalidCoreMLArtifacts: sortedInvalidBundles
            ))
        }
        if !sortedMissingArtifacts.isEmpty {
            return ParakeetModelValidation(status: .missingArtifacts(sortedMissingArtifacts))
        }
        if !sortedInvalidBundles.isEmpty {
            return ParakeetModelValidation(status: .invalidCoreMLArtifacts(sortedInvalidBundles))
        }
        return ParakeetModelValidation(status: .complete)
    }

    static func modelsExist(
        variant: ParakeetModelVariant,
        fileManager: FileManager = .default
    ) -> Bool {
        let directory = modelDirectory(for: variant)
        guard validation(at: directory, variant: variant, fileManager: fileManager).isComplete else {
            return false
        }
        return AsrModels.modelsExist(
            at: directory,
            version: variant.asrVersion,
            encoderPrecision: variant.encoderPrecision
        )
    }

    private static func requiredArtifacts(for variant: ParakeetModelVariant) -> [String] {
        let models: Set<String>
        switch variant {
        case .v3:
            models = ModelNames.ASR.requiredModelsV3(precision: variant.encoderPrecision)
        case .v2:
            models = ModelNames.ASR.requiredModels
        }
        return (models + [ModelNames.ASR.vocabularyFile]).sorted()
    }

    private static func rawNVIDIARepositoryMarkers(
        at directory: URL,
        fileManager: FileManager
    ) -> [String] {
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else {
            return []
        }
        let lowercasedNames = names.map { $0.lowercased() }
        let markerNames = [
            "model_config.yaml",
            "preprocessor_config.json",
            "pytorch_model.bin",
            "model.safetensors",
            "model.safetensors.index.json",
            "tokenizer.model"
        ]
        var markers = markerNames.filter { lowercasedNames.contains($0) }
        if lowercasedNames.contains(where: { $0.hasSuffix(".nemo") }) {
            markers.append("*.nemo")
        }
        return markers.sorted()
    }

    enum ParakeetModelError: Error, LocalizedError {
        case unsupportedPlatform
        case invalidModel(ParakeetModelValidation)
        case loadFailed(underlying: Error)
        case notInstalled

        var errorDescription: String? {
            switch self {
            case .unsupportedPlatform:
                "Parakeet requires an Apple Silicon Mac."
            case .invalidModel(let validation):
                "\(validation.message) Expected the FluidAudio Core ML conversion for the selected model."
            case .loadFailed:
                "The FluidAudio Core ML model could not be loaded. Remove the partial bundle and download it again."
            case .notInstalled:
                "The selected Parakeet model is not installed."
            }
        }
    }
}

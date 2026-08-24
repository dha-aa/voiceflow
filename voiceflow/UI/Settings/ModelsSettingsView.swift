//
//  ModelsSettingsView.swift
//  VoiceFlow
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ModelsSettingsView: View {
    @Bindable var modelManager: ModelManager
    @Bindable var downloadCoordinator: ModelDownloadCoordinator
    @Bindable var speechRecognitionSettings: SpeechRecognitionSettings
    @Bindable var parakeetModelManager: ParakeetModelManager
    @State private var pendingDeletion: WhisperModel?
    @State private var pendingFluidAudioDeletion: ParakeetModelVariant?
    @State private var showingActiveModelAlert = false
    @State private var errorMessage: String?
    @State private var isImporting = false
    @State private var showingModelImporter = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    speechEngineSection
                    providerModelsList
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if modelManager.isRefreshing {
                ProgressView("Refreshing model catalog...")
                    .controlSize(.small)
                    .padding(.top, 12)
            }
            if isImporting {
                ProgressView("Importing and validating model...")
                    .controlSize(.small)
                    .padding(.top, 8)
            }
        }
        .padding(24)
        .navigationTitle("Models")
        .task {
            if modelManager.availableModels.isEmpty && !downloadCoordinator.isDownloading && !modelManager.isRefreshing {
                refreshModels()
            }
        }
        .fileImporter(
            isPresented: $showingModelImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            importModel(from: result)
        }
        .alert(
            "Delete model?",
            isPresented: deleteAlertBinding,
            presenting: pendingDeletion
        ) { model in
            Button("Delete", role: .destructive) {
                delete(model)
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeletion = nil
            }
        } message: { model in
            Text("Delete \(model.displayName) from this Mac? This cannot be undone.")
        }
        .alert("Delete FluidAudio model?", isPresented: fluidAudioDeleteAlertBinding) {
            Button("Delete", role: .destructive) {
                if let variant = pendingFluidAudioDeletion {
                    delete(variant)
                }
                pendingFluidAudioDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                pendingFluidAudioDeletion = nil
            }
        } message: {
            Text("Delete this FluidAudio model from this Mac? This cannot be undone.")
        }
        .alert("Active model cannot be deleted", isPresented: $showingActiveModelAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Select another installed model as active before deleting this model.")
        }
        .alert("Model action failed", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) {
                downloadCoordinator.dismissError()
                parakeetModelManager.dismissError()
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? downloadCoordinator.errorMessage ?? parakeetModelManager.errorMessage ?? "Unknown model error")
        }
    }

    static func parakeetActionTitle(isLoading: Bool, isInstalled: Bool) -> String {
        if isLoading { return "Cancel" }
        if isInstalled { return "Open Folder" }
        return "Download"
    }

    private var header: some View {
        HStack {
            Text("Models")
                .font(.title2.bold())
            Spacer()
            Button {
                showingModelImporter = true
            } label: {
                Label("Import Model", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)
            .help("Import a WhisperKit Core ML model folder")
            .disabled(isImporting || modelManager.isRefreshing || downloadCoordinator.isDownloading)
            Button {
                refreshModels()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh available WhisperKit models")
            .disabled(modelManager.isRefreshing || downloadCoordinator.isDownloading)
        }
        .padding(.bottom, 12)
    }

    private var speechEngineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Speech recognition", selection: Binding(
                get: { speechRecognitionSettings.selectedEngine },
                set: { speechRecognitionSettings.selectEngine($0) }
            )) {
                ForEach(SpeechRecognitionSettings.Engine.allCases) { engine in
                    Text(engine.displayName).tag(engine)
                }
            }
            .pickerStyle(.menu)

            if speechRecognitionSettings.selectedEngine == .parakeet {
                Text("FluidAudio models")
                    .font(.headline)

                Text("\(parakeetModelManager.selectedVariant.languageDescription) · FluidAudio Core ML")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("VoiceFlow uses the FluidInference Core ML conversion. The NVIDIA upstream NeMo/Transformers repository cannot be loaded directly.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

            }
        }
        .padding(.bottom, 12)
    }

    static func showsWhisperModels(for engine: SpeechRecognitionSettings.Engine) -> Bool {
        engine == .whisperKit
    }

    static func showsFluidAudioDelete(isDownloaded: Bool) -> Bool {
        isDownloaded
    }

    @ViewBuilder
    private var providerModelsList: some View {
        if Self.showsWhisperModels(for: speechRecognitionSettings.selectedEngine) {
            modelsList
        } else {
            fluidAudioModelsList
        }
    }

    private var fluidAudioModelsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(ParakeetModelManager.availableVariants) { variant in
                FluidAudioModelRow(
                    variant: variant,
                    validation: parakeetModelManager.validation(for: variant),
                    isDownloaded: parakeetModelManager.isInstalled(for: variant),
                    isActive: parakeetModelManager.isActive(variant),
                    isSelected: parakeetModelManager.selectedVariant == variant,
                    isLoading: parakeetModelManager.isLoading && parakeetModelManager.selectedVariant == variant,
                    isDownloadBlocked: parakeetModelManager.isLoading && parakeetModelManager.selectedVariant != variant,
                    progress: parakeetModelManager.selectedVariant == variant ? parakeetModelManager.progress : 0,
                    isCancelling: parakeetModelManager.isCancelling,
                    onSelect: {
                        parakeetModelManager.selectVariant(variant)
                    },
                    onDownload: {
                        parakeetModelManager.selectVariant(variant)
                        startParakeetDownload(force: parakeetModelManager.needsRepair)
                    },
                    onCancel: {
                        parakeetModelManager.cancelDownload()
                    },
                    onDelete: {
                        requestDelete(variant)
                    }
                )
                Divider()
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Model location")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Button {
                        NSWorkspace.shared.open(parakeetModelManager.modelDirectory)
                    } label: {
                        Label("Open in Finder", systemImage: "folder")
                    }
                    .buttonStyle(.borderless)
                }
                Text(parakeetModelManager.modelDirectory.path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .padding(.top, 4)
        }
    }

    private var modelsList: some View {
        VStack(alignment: .leading, spacing: 18) {
            ModelSectionView(
                title: "Installed Models",
                models: installedModels,
                emptyText: "No models installed yet.",
                activeDownloadID: downloadCoordinator.activeModelID,
                downloadProgress: downloadCoordinator.progress,
                isCancelling: downloadCoordinator.isCancelling,
                onSetActive: setActive,
                onDownload: startDownload,
                onCancel: cancelDownload,
                onDelete: requestDelete
            )

            ModelSectionView(
                title: "Available to Download",
                models: downloadableModels,
                emptyText: "No additional models are currently available.",
                activeDownloadID: downloadCoordinator.activeModelID,
                downloadProgress: downloadCoordinator.progress,
                isCancelling: downloadCoordinator.isCancelling,
                onSetActive: setActive,
                onDownload: startDownload,
                onCancel: cancelDownload,
                onDelete: requestDelete
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Model location")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Button {
                        NSWorkspace.shared.open(modelManager.downloadBase)
                    } label: {
                        Label("Open in Finder", systemImage: "folder")
                    }
                    .buttonStyle(.borderless)
                }
                Text(modelManager.downloadBase.path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .padding(.top, 4)
        }
    }

    private var installedModels: [WhisperModel] {
        modelManager.availableModels.filter { $0.isDownloaded }
    }

    private var downloadableModels: [WhisperModel] {
        modelManager.availableModels.filter { !$0.isDownloaded }
    }

    private var fluidAudioDeleteAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingFluidAudioDeletion != nil },
            set: { if !$0 { pendingFluidAudioDeletion = nil } }
        )
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil || downloadCoordinator.errorMessage != nil || parakeetModelManager.errorMessage != nil },
            set: {
                if !$0 {
                    errorMessage = nil
                    downloadCoordinator.dismissError()
                    parakeetModelManager.dismissError()
                }
            }
        )
    }

    private func setActive(_ model: WhisperModel) {
        modelManager.selectModel(id: model.id)
    }

    private func startDownload(_ model: WhisperModel) {
        downloadCoordinator.startDownload(id: model.id)
    }

    private func startParakeetDownload(force: Bool = false) {
        if force {
            do {
                try parakeetModelManager.repair()
            } catch {
                errorMessage = errorDescription(for: error)
                return
            }
        }
        parakeetModelManager.startDownload()
    }

    private func cancelDownload() {
        downloadCoordinator.cancelDownload()
    }

    private func requestDelete(_ model: WhisperModel) {
        if model.isActive {
            showingActiveModelAlert = true
        } else {
            pendingDeletion = model
        }
    }

    private func requestDelete(_ variant: ParakeetModelVariant) {
        pendingFluidAudioDeletion = variant
    }

    private func delete(_ variant: ParakeetModelVariant) {
        do {
            try parakeetModelManager.delete(variant)
        } catch {
            errorMessage = errorDescription(for: error)
        }
    }

    private func delete(_ model: WhisperModel) {
        do {
            try modelManager.deleteModel(id: model.id)
            Task { @MainActor in
                try? await modelManager.refreshModels()
            }
        } catch {
            errorMessage = errorDescription(for: error)
        }
    }

    private func importModel(from result: Result<[URL], Error>) {
        let source: URL
        switch result {
        case .success(let urls):
            guard let selectedURL = urls.first else {
                errorMessage = "No model folder was selected."
                return
            }
            source = selectedURL
        case .failure(let error):
            errorMessage = errorDescription(for: error)
            return
        }

        isImporting = true
        Task { @MainActor in
            let accessed = source.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    source.stopAccessingSecurityScopedResource()
                }
                isImporting = false
            }
            do {
                try await modelManager.importCustomModel(from: source)
                try await modelManager.refreshModels()
            } catch {
                errorMessage = errorDescription(for: error)
            }
        }
    }

    private func refreshModels() {
        guard !modelManager.isRefreshing, !isImporting, !downloadCoordinator.isDownloading else { return }
        Task { @MainActor in
            do {
                try await modelManager.refreshModels()
            } catch {
                errorMessage = errorDescription(for: error)
            }
        }
    }

    private func errorDescription(for error: Error) -> String {
        if let parakeetError = error as? ParakeetModelManager.ParakeetModelError {
            return parakeetError.localizedDescription
        }
        if let modelError = error as? ModelManager.ModelManagerError {
            switch modelError {
            case .invalidModelIdentifier: return "The model identifier is invalid."
            case .modelAlreadyInstalled: return "This model is already installed."
            case .modelNotDownloaded: return "The model is not installed."
            case .invalidModelDirectory: return "The downloaded model failed validation."
            case .modelLoadFailed: return "The downloaded model could not be loaded by WhisperKit."
            case .cannotDeleteActiveModel: return "Select another active model before deleting this model."
            case .deleteVerificationFailed: return "The model could not be fully removed."
            }
        }
        return error.localizedDescription
    }
}

private struct FluidAudioModelRow: View {
    let variant: ParakeetModelVariant
    let validation: ParakeetModelValidation
    let isDownloaded: Bool
    let isActive: Bool
    let isSelected: Bool
    let isLoading: Bool
    let isDownloadBlocked: Bool
    let progress: Double
    let isCancelling: Bool
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isActive ? .green : .secondary)
                .font(.title3)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(variant.displayName)
                        .font(.body.weight(.medium))
                    if isActive {
                        Text("Active")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                }
                Text(variant.languageDescription + " · " + (isDownloaded ? "Downloaded" : validation.message))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if isLoading {
                    HStack(spacing: 8) {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .frame(maxWidth: 170)
                        Text("\(Int(progress * 100))%")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Button(isCancelling ? "Cancelling…" : "Cancel", action: onCancel)
                            .buttonStyle(.borderless)
                            .disabled(isCancelling)
                    }
                }
            }

            Spacer(minLength: 8)

            if isDownloaded {
                if !isActive {
                    Button("Set Active", action: onSelect)
                        .buttonStyle(.bordered)
                }
                Button("Delete", role: .destructive, action: onDelete)
                    .buttonStyle(.bordered)
            } else if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button("Download", action: onDownload)
                    .buttonStyle(.borderedProminent)
                    .disabled(isDownloadBlocked)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct ModelSectionView: View {
    let title: String
    let models: [WhisperModel]
    let emptyText: String
    let activeDownloadID: String?
    let downloadProgress: Double
    let isCancelling: Bool
    let onSetActive: (WhisperModel) -> Void
    let onDownload: (WhisperModel) -> Void
    let onCancel: () -> Void
    let onDelete: (WhisperModel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            if models.isEmpty {
                Text(emptyText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                ForEach(models) { model in
                    ModelRow(
                        model: model,
                        activeDownloadID: activeDownloadID,
                        downloadProgress: downloadProgress,
                        isCancelling: isCancelling,
                        onSetActive: { onSetActive(model) },
                        onDownload: { onDownload(model) },
                        onCancel: onCancel,
                        onDelete: { onDelete(model) }
                    )
                    Divider()
                }
            }
        }
    }
}

private struct ModelRow: View {
    let model: WhisperModel
    let activeDownloadID: String?
    let downloadProgress: Double
    let isCancelling: Bool
    let onSetActive: () -> Void
    let onDownload: () -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: model.isActive ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(model.isActive ? .green : .secondary)
                .font(.title3)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(model.displayName)
                        .font(.body.weight(.medium))
                    if model.isRecommended {
                        Text("Recommended")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if activeDownloadID == model.id {
                    HStack(spacing: 8) {
                        ProgressView(value: downloadProgress)
                            .progressViewStyle(.linear)
                            .frame(maxWidth: 150)
                        Text("\(Int(downloadProgress * 100))%")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Button(isCancelling ? "Cancelling…" : "Cancel", action: onCancel)
                            .buttonStyle(.borderless)
                            .disabled(isCancelling)
                    }
                }
            }

            Spacer(minLength: 8)

            if model.isDownloaded {
                if model.isActive {
                    Text("Active")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                } else {
                    Button("Set Active", action: onSetActive)
                        .buttonStyle(.bordered)
                }
                Button("Delete", role: .destructive, action: onDelete)
                    .buttonStyle(.bordered)
            } else if activeDownloadID == model.id {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button("Download", action: onDownload)
                    .buttonStyle(.borderedProminent)
                    .disabled(activeDownloadID != nil)
            }
        }
        .padding(.vertical, 6)
    }

    private var detailText: String {
        let size = model.sizeOnDisk.map {
            ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
        } ?? "Size unknown"
        return model.isDownloaded ? "\(size) · Downloaded" : size
    }
}

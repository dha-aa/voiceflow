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
        FluidAudioModelsSection(
            parakeetModelManager: parakeetModelManager,
            onSelect: { variant in
                parakeetModelManager.selectVariant(variant)
            },
            onDownload: { variant in
                parakeetModelManager.selectVariant(variant)
                startParakeetDownload(force: parakeetModelManager.needsRepair)
            },
            onCancel: {
                parakeetModelManager.cancelDownload()
            },
            onDelete: { variant in
                requestDelete(variant)
            }
        )
    }

    private var modelsList: some View {
        WhisperModelsSection(
            modelManager: modelManager,
            downloadCoordinator: downloadCoordinator,
            onSetActive: setActive,
            onDownload: startDownload,
            onCancel: cancelDownload,
            onDelete: requestDelete
        )
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

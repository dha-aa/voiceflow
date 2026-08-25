//
//  WhisperModelsSection.swift
//  VoiceFlow
//
//  WhisperKit model lists and managed-folder presentation.
//

import AppKit
import SwiftUI

struct WhisperModelsSection: View {
    @Bindable var modelManager: ModelManager
    @Bindable var downloadCoordinator: ModelDownloadCoordinator
    let onSetActive: (WhisperModel) -> Void
    let onDownload: (WhisperModel) -> Void
    let onCancel: () -> Void
    let onDelete: (WhisperModel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ModelSectionView(
                title: "Installed Models",
                models: installedModels,
                emptyText: "No models installed yet.",
                activeDownloadID: downloadCoordinator.activeModelID,
                downloadProgress: downloadCoordinator.progress,
                isCancelling: downloadCoordinator.isCancelling,
                onSetActive: onSetActive,
                onDownload: onDownload,
                onCancel: onCancel,
                onDelete: onDelete
            )

            ModelSectionView(
                title: "Available to Download",
                models: downloadableModels,
                emptyText: "No additional models are currently available.",
                activeDownloadID: downloadCoordinator.activeModelID,
                downloadProgress: downloadCoordinator.progress,
                isCancelling: downloadCoordinator.isCancelling,
                onSetActive: onSetActive,
                onDownload: onDownload,
                onCancel: onCancel,
                onDelete: onDelete
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
        modelManager.availableModels.filter(\.isDownloaded)
    }

    private var downloadableModels: [WhisperModel] {
        modelManager.availableModels.filter { !$0.isDownloaded }
    }
}

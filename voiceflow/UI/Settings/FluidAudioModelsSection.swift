//
//  FluidAudioModelsSection.swift
//  VoiceFlow
//
//  FluidAudio model list and managed-folder presentation.
//

import AppKit
import SwiftUI

struct FluidAudioModelsSection: View {
    @Bindable var parakeetModelManager: ParakeetModelManager
    let onSelect: (ParakeetModelVariant) -> Void
    let onDownload: (ParakeetModelVariant) -> Void
    let onCancel: () -> Void
    let onDelete: (ParakeetModelVariant) -> Void

    var body: some View {
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
                    onSelect: { onSelect(variant) },
                    onDownload: { onDownload(variant) },
                    onCancel: onCancel,
                    onDelete: { onDelete(variant) }
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
}

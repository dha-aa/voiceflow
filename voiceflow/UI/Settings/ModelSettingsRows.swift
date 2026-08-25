//
//  ModelSettingsRows.swift
//  VoiceFlow
//
//  Reusable model-provider rows used by the Models Settings screen.
//

import SwiftUI

struct FluidAudioModelRow: View {
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

struct ModelSectionView: View {
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

struct ModelRow: View {
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

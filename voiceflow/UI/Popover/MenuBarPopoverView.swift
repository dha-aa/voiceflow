//
//  MenuBarPopoverView.swift
//  VoiceFlow
//

import AppKit
import SwiftUI

struct MenuBarPopoverView: View {
    @Bindable var stateManager: AppStateManager
    @Bindable var modelManager: ModelManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.circle.fill")
                    .foregroundStyle(.tint)
                Text("VoiceFlow")
                    .font(.headline)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(statusText)
                    .font(.subheadline.weight(.medium))
                Text(activeModelText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Divider()

            Button {
                SettingsWindowController.shared.show(modelManager: modelManager)
            } label: {
                Label("Settings...", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit VoiceFlow", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
        }
        .padding(16)
        .frame(width: 230, height: 178)
    }

    private var statusText: String {
        switch stateManager.currentState {
        case .idle: "Ready"
        case .completed: "Done"
        case .preparingModel: "Loading model"
        case .recording: "Listening"
        case .processing: "Processing"
        case .injecting: "Injecting"
        case .error: "Error"
        }
    }

    private var activeModelText: String {
        guard let selectedID = modelManager.selectedModelId else {
            return "No active model"
        }
        let displayName = modelManager.availableModels
            .first { $0.id == selectedID }?.displayName ?? selectedID
        return "Model: \(displayName)"
    }
}

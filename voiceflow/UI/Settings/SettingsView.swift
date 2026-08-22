//
//  SettingsView.swift
//  VoiceFlow
//

import SwiftUI

struct SettingsView: View {
    enum Destination: String, CaseIterable, Identifiable, Hashable {
        case general
        case models
        case about

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: "General"
            case .models: "Models"
            case .about: "About"
            }
        }

        var systemImage: String {
            switch self {
            case .general: "gearshape"
            case .models: "cpu"
            case .about: "info.circle"
            }
        }
    }

    let modelManager: ModelManager
    let downloadCoordinator: ModelDownloadCoordinator
    @State private var selection: Destination = .general

    var body: some View {
        NavigationSplitView {
            List {
                ForEach(Destination.allCases) { destination in
                    Button {
                        withAnimation(.easeInOut(duration: 0.12)) {
                            selection = destination
                        }
                    } label: {
                        Label(destination.title, systemImage: destination.systemImage)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 5)
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(selection == destination ? Color.accentColor.opacity(0.18) : .clear)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Settings")
            .frame(minWidth: 170)
        } detail: {
            detailView(for: selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private func detailView(for destination: Destination) -> some View {
        switch destination {
        case .general:
            GeneralSettingsView()
                        case .models:
                    ModelsSettingsView(
                        modelManager: modelManager,
                        downloadCoordinator: downloadCoordinator
                    )

        case .about:
            AboutSettingsView()
        }
    }
}

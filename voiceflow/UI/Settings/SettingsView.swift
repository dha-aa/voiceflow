//
//  SettingsView.swift
//  VoiceFlow
//

import SwiftUI

struct SettingsView: View {
    enum Destination: String, CaseIterable, Identifiable, Hashable {
        case general
        case ai
        case models
        case about

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: "General"
            case .ai: "AI"
            case .models: "Models"
            case .about: "About"
            }
        }

        var systemImage: String {
            switch self {
            case .general: "gearshape"
            case .ai: "sparkles"
            case .models: "cpu"
            case .about: "info.circle"
            }
        }
    }

    let modelManager: ModelManager
    let downloadCoordinator: ModelDownloadCoordinator
    let speechRecognitionSettings: SpeechRecognitionSettings
    let parakeetModelManager: ParakeetModelManager
    @State private var selection: Destination = .general
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    static func sidebarToggleTitle(isSidebarVisible: Bool) -> String {
        isSidebarVisible ? "Hide Sidebar" : "Show Sidebar"
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
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
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
                    }
                } label: {
                    Label(
                        Self.sidebarToggleTitle(isSidebarVisible: columnVisibility != .detailOnly),
                        systemImage: "sidebar.left"
                    )
                }
                .help(Self.sidebarToggleTitle(isSidebarVisible: columnVisibility != .detailOnly))
            }
        }
    }

    @ViewBuilder
    private func detailView(for destination: Destination) -> some View {
        switch destination {
        case .general:
            GeneralSettingsView()
        case .ai:
            AISettingsView()
        case .models:
            ModelsSettingsView(
                modelManager: modelManager,
                downloadCoordinator: downloadCoordinator,
                speechRecognitionSettings: speechRecognitionSettings,
                parakeetModelManager: parakeetModelManager
            )

        case .about:
            AboutSettingsView()
        }
    }
}

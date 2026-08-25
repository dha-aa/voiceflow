//
//  SettingsWindowController.swift
//  VoiceFlow
//

import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private static let intendedContentSize = NSSize(width: 760, height: 500)
    private static let minimumContentSize = NSSize(width: 680, height: 420)

    private var modelManager: ModelManager?
    private var speechRecognitionSettings: SpeechRecognitionSettings?
    private var parakeetModelManager: ParakeetModelManager?
    private var snippetStore: SnippetStore?
    private var audioRetentionManager: AudioRetentionManager?
    private var aiSettingsService: AISettingsService?
    private var permissionManager: VoiceFlowPermissionManaging?
    private var downloadCoordinator: ModelDownloadCoordinator?

    private init() {
        super.init(window: nil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func show(
        modelManager: ModelManager,
        speechRecognitionSettings: SpeechRecognitionSettings,
        parakeetModelManager: ParakeetModelManager,
        snippetStore: SnippetStore,
        audioRetentionManager: AudioRetentionManager,
        aiSettingsService: AISettingsService,
        permissionManager: VoiceFlowPermissionManaging,
        downloadCoordinator: ModelDownloadCoordinator
    ) {
        self.modelManager = modelManager
        self.speechRecognitionSettings = speechRecognitionSettings
        self.parakeetModelManager = parakeetModelManager
        self.snippetStore = snippetStore
        self.audioRetentionManager = audioRetentionManager
        self.aiSettingsService = aiSettingsService
        self.permissionManager = permissionManager
        self.downloadCoordinator = downloadCoordinator

        if let window {
            window.contentViewController = NSHostingController(
                rootView: SettingsView(
                    modelManager: modelManager,
                    downloadCoordinator: downloadCoordinator,
                    speechRecognitionSettings: speechRecognitionSettings,
                    parakeetModelManager: parakeetModelManager,
                    snippetStore: snippetStore,
                    audioRetentionManager: audioRetentionManager,
                    aiSettingsService: aiSettingsService,
                    permissionManager: permissionManager
                )
            )
            resetWindowGeometry(window)
            window.makeKeyAndOrderFront(nil)
        } else {
            let settingsWindow = NSWindow(
                contentRect: NSRect(
                    origin: .zero,
                    size: Self.intendedContentSize
                ),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            settingsWindow.title = "VoiceFlow Settings"
            settingsWindow.center()
            settingsWindow.isReleasedWhenClosed = false
            settingsWindow.minSize = Self.minimumContentSize
            settingsWindow.contentMinSize = Self.minimumContentSize
            settingsWindow.contentViewController = NSHostingController(
                rootView: SettingsView(
                    modelManager: modelManager,
                    downloadCoordinator: downloadCoordinator,
                    speechRecognitionSettings: speechRecognitionSettings,
                    parakeetModelManager: parakeetModelManager,
                    snippetStore: snippetStore,
                    audioRetentionManager: audioRetentionManager,
                    aiSettingsService: aiSettingsService,
                    permissionManager: permissionManager
                )
            )
            self.window = settingsWindow
            settingsWindow.makeKeyAndOrderFront(nil)
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func show() {
        guard let modelManager,
              let speechRecognitionSettings,
              let parakeetModelManager,
              let snippetStore,
              let audioRetentionManager,
              let aiSettingsService,
              let permissionManager,
              let downloadCoordinator else { return }
        show(
            modelManager: modelManager,
            speechRecognitionSettings: speechRecognitionSettings,
            parakeetModelManager: parakeetModelManager,
            snippetStore: snippetStore,
            audioRetentionManager: audioRetentionManager,
            aiSettingsService: aiSettingsService,
            permissionManager: permissionManager,
            downloadCoordinator: downloadCoordinator
        )
    }

    private func resetWindowGeometry(_ window: NSWindow) {
        window.minSize = Self.minimumContentSize
        window.contentMinSize = Self.minimumContentSize

        var frame = window.frame
        let center = NSPoint(x: frame.midX, y: frame.midY)
        frame.size = Self.intendedContentSize
        frame.origin = NSPoint(
            x: center.x - (Self.intendedContentSize.width / 2),
            y: center.y - (Self.intendedContentSize.height / 2)
        )
        window.setFrame(frame, display: true, animate: false)
        window.setContentSize(Self.intendedContentSize)
    }
}

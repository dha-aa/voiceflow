//
//  MenuBarController.swift
//  VoiceFlow
//

import AppKit
import SwiftUI

@MainActor
final class MenuBarController {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let stateManager: AppStateManager
    private let modelManager: ModelManager
    private let speechRecognitionSettings: SpeechRecognitionSettings
    private let parakeetModelManager: ParakeetModelManager
    private let snippetStore: SnippetStore
    private let audioRetentionManager: AudioRetentionManager
    private let aiSettingsService: AISettingsService
    private var stateTimer: Timer?
    private var animationTimer: Timer?
    private var lastState: AppState?
    private var animationFrame = false

    init(
        stateManager: AppStateManager,
        modelManager: ModelManager,
        speechRecognitionSettings: SpeechRecognitionSettings,
        parakeetModelManager: ParakeetModelManager,
        snippetStore: SnippetStore,
        audioRetentionManager: AudioRetentionManager,
        aiSettingsService: AISettingsService
    ) {
        self.stateManager = stateManager
        self.modelManager = modelManager
        self.speechRecognitionSettings = speechRecognitionSettings
        self.parakeetModelManager = parakeetModelManager
        self.snippetStore = snippetStore
        self.audioRetentionManager = audioRetentionManager
        self.aiSettingsService = aiSettingsService
        setupStatusItem()
        setupPopover()
        startStateObservation()
    }

    deinit {
        stateTimer?.invalidate()
        animationTimer?.invalidate()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.action = #selector(statusBarButtonClicked)
            button.target = self
            button.setAccessibilityLabel("VoiceFlow")
            updateIcon(for: .idle)
        }
    }

    private func setupPopover() {
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 200, height: 150)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(
            rootView: MenuBarPopoverView(
                stateManager: stateManager,
                modelManager: modelManager,
                                    speechRecognitionSettings: speechRecognitionSettings,
                    parakeetModelManager: parakeetModelManager,
                    snippetStore: snippetStore,
                    audioRetentionManager: audioRetentionManager,
                    aiSettingsService: aiSettingsService
                )

        )
    }

    private func startStateObservation() {
        stateTimer = Timer.scheduledTimer(withTimeInterval: 0.10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let state = self.stateManager.currentState
                guard state != self.lastState else { return }
                self.lastState = state
                self.updateIcon(for: state)
            }
        }
    }

    func updateIcon(for state: AppState) {
        stopAnimationTimer()

        switch state {
        case .idle, .completed, .copiedToClipboard:
            setMenuBarIcon(alpha: 1)

        case .recording:
            setIcon(symbolName: "mic.fill", tint: .systemRed, alpha: 1)
            animationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.animationFrame.toggle()
                    self.setIcon(
                        symbolName: self.animationFrame ? "mic.fill" : "mic",
                        tint: .systemRed,
                        alpha: self.animationFrame ? 1.0 : 0.72
                    )
                }
            }

        case .preparingModel, .processing, .injecting:
            setIcon(symbolName: "waveform", tint: nil, alpha: 1)
            animationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.animationFrame.toggle()
                    self.setIcon(
                        symbolName: self.animationFrame ? "waveform" : "waveform.path.ecg",
                        tint: nil,
                        alpha: self.animationFrame ? 1.0 : 0.68
                    )
                }
            }

        case .error:
            setIcon(symbolName: "exclamationmark.triangle", tint: .systemOrange, alpha: 1)
        }
    }

    private func setMenuBarIcon(alpha: CGFloat) {
        guard let button = statusItem?.button else { return }
        guard let image = NSImage(named: NSImage.Name("MenuBarIcon")) else {
            setIcon(symbolName: "waveform", tint: nil, alpha: alpha)
            return
        }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        button.image = image
        button.contentTintColor = nil
        button.imageScaling = .scaleProportionallyDown
        button.alphaValue = alpha
    }

    private func setIcon(symbolName: String, tint: NSColor?, alpha: CGFloat) {
        guard let button = statusItem?.button else { return }
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "VoiceFlow") else { return }
        image.isTemplate = true
        button.image = image
        // A nil tint lets NSStatusBar/AppKit derive the foreground color from
        // the current menu-bar appearance: dark in Light Mode and light in
        // Dark Mode. Explicit semantic colors remain available for active and
        // error states.
        button.contentTintColor = tint
        button.alphaValue = alpha
    }

    private func stopAnimationTimer() {
        animationTimer?.invalidate()
        animationTimer = nil
        animationFrame = false
    }

    @objc private func statusBarButtonClicked() {
        guard let popover else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem?.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func showPopover() {
        guard let popover, let button = statusItem?.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func hidePopover() {
        popover?.performClose(nil)
    }
}


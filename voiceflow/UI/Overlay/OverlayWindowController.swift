//
//  OverlayWindowController.swift
//  VoiceFlow
//

import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class OverlayWindowController {
    let overlayModel: RecordingOverlayModel

    private let stateManager: AppStateManager
    private weak var audioRecorder: AudioRecorder?
    private let userDefaults: UserDefaults
    private let panel: NonActivatingPanel
    private var stateTimer: Timer?
    private var audioLevelTimer: Timer?
    private var interactionTask: Task<Void, Never>?
    private var lastObservedState: AppState?
    private var panelAnimationGeneration = 0
    private var defaultsObserver: NSObjectProtocol?
    private var isStarted = false

    init(
        stateManager: AppStateManager,
        audioRecorder: AudioRecorder? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        self.stateManager = stateManager
        self.audioRecorder = audioRecorder
        self.userDefaults = userDefaults
        self.overlayModel = RecordingOverlayModel()
        self.panel = NonActivatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 270, height: 58),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        configurePanel()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: userDefaults,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateOverlay(for: self.stateManager.currentState)
            }
        }
    }

    deinit {
        stateTimer?.invalidate()
        audioLevelTimer?.invalidate()
        interactionTask?.cancel()
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
    }

    var isFocusSafe: Bool {
        panel.styleMask.contains(.nonactivatingPanel) &&
            !panel.canBecomeKey &&
            !panel.canBecomeMain
    }

    var appearsAcrossSpaces: Bool {
        panel.collectionBehavior.contains(.canJoinAllSpaces)
    }

    var overlayFrame: NSRect {
        panel.frame
    }

    var hasNativePanelShadow: Bool {
        panel.hasShadow
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        positionAtBottomCenter()
        updateOverlay(for: stateManager.currentState)

        stateTimer = Timer.scheduledTimer(withTimeInterval: 0.10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let state = self.stateManager.currentState
                guard state != self.lastObservedState else { return }
                self.lastObservedState = state
                self.updateOverlay(for: state)
            }
        }

        // Sampling is capped at 30 Hz to keep waveform rendering inexpensive.
        audioLevelTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.overlayModel.updateAudioLevel(self.audioRecorder?.audioLevel ?? 0)
            }
        }
    }

    func stop() {
        isStarted = false
        stateTimer?.invalidate()
        stateTimer = nil
        audioLevelTimer?.invalidate()
        audioLevelTimer = nil
        interactionTask?.cancel()
        interactionTask = nil
        hideOverlay(animated: false)
    }

    func updateOverlay(for state: AppState) {
        if !shouldShowOverlay {
            interactionTask?.cancel()
            interactionTask = nil
            overlayModel.hide()
            hidePanel(animated: true)
            return
        }

        // The core pipeline can reach idle immediately after injecting. Let
        // the overlay-owned Done timer finish its short presentation.
        if state == .idle, overlayModel.isShowingCompletionState {
            return
        }

        interactionTask?.cancel()
        interactionTask = nil

        switch state {
        case .idle:
            // The core pipeline can reach idle immediately after injecting. Let
            // the overlay-owned Done timer finish its 400 ms presentation.
            guard !overlayModel.isShowingCompletionState else { return }
            overlayModel.hide()
            hidePanel(animated: true)

        case .preparingModel:
            overlayModel.showPreparingModelState()
            showPanel()

        case .recording:
            overlayModel.showListeningState()
            showPanel()

        case .processing:
            overlayModel.showProcessingState()
            showPanel()

        case .injecting:
            overlayModel.showProcessingState()
            showPanel()

        case .completed:
            overlayModel.showDoneState()
            showPanel()
            interactionTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(for: .milliseconds(400))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                self?.hideOverlay(animated: true)
            }

        case .copiedToClipboard:
            overlayModel.showCopiedToClipboardState()
            showPanel()
            interactionTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(for: .milliseconds(400))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                self?.hideOverlay(animated: true)
            }

        case .error(let error):
            overlayModel.showErrorState(error)
            showPanel()
        }
    }

    func showAIProcessing(for provider: AIProvider) {
        guard shouldShowOverlay else { return }
        overlayModel.showAIProcessingState(provider: provider)
        showPanel()
    }

    func showOverlay() {
        guard shouldShowOverlay else { return }
        showPanel()
    }

    func hideOverlay() {
        hideOverlay(animated: true)
    }

    private var shouldShowOverlay: Bool {
        userDefaults.object(forKey: "showRecordingOverlay") as? Bool ?? true
    }

    private func configurePanel() {
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .transient, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // The SwiftUI capsule owns the only shadow. A panel-level shadow is
        // rectangular and can create a visible gray halo around the pill.
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.animationBehavior = .none
        let hostingView = NSHostingView(rootView: RecordingOverlayView(model: overlayModel))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.isOpaque = false
        panel.contentView = hostingView
        panel.alphaValue = 0
        panel.orderOut(nil)
    }

    private func positionAtBottomCenter() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visibleFrame = screen.visibleFrame
        let size = NSSize(width: 270, height: 58)
        let origin = NSPoint(
            x: visibleFrame.midX - (size.width / 2),
            y: visibleFrame.minY + 24
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
    }

    private func showPanel() {
        panelAnimationGeneration += 1
        positionAtBottomCenter()
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        } else {
            panel.orderFrontRegardless()
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        // A previous hide animation may still be finishing. Its completion is
        // generation-checked below, so it cannot order out this presentation.
    }

    private func hideOverlay(animated: Bool) {
        overlayModel.hide()
        hidePanel(animated: animated)
    }

    private func hidePanel(animated: Bool) {
        panelAnimationGeneration += 1
        let generation = panelAnimationGeneration

        guard panel.isVisible else {
            panel.orderOut(nil)
            return
        }

        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.panelAnimationGeneration == generation else { return }
                    self.panel.orderOut(nil)
                }
            })
        } else {
            panel.alphaValue = 0
            panel.orderOut(nil)
        }
    }
}

private final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

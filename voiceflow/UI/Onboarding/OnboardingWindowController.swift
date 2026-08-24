//
//  OnboardingWindowController.swift
//  VoiceFlow
//
//  First-launch onboarding window lifecycle.
//

import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    static let shared = OnboardingWindowController()

    private static let contentSize = NSSize(width: 600, height: 520)
    private var onboardingModel: OnboardingModel?
    private var isFinishing = false

    private init() {
        super.init(window: nil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    static func shouldShowOnLaunch(userDefaults: UserDefaults = .standard) -> Bool {
        !userDefaults.bool(forKey: VoiceFlowOnboardingDefaults.completedKey)
    }

    func showIfNeeded(userDefaults: UserDefaults = .standard) {
        guard Self.shouldShowOnLaunch(userDefaults: userDefaults) else { return }
        show(userDefaults: userDefaults)
    }

    func show(userDefaults: UserDefaults = .standard) {
        guard Self.shouldShowOnLaunch(userDefaults: userDefaults) else { return }
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let model = OnboardingModel(
            userDefaults: userDefaults,
            onFinished: { [weak self] in
                self?.finish()
            }
        )
        onboardingModel = model

        let onboardingWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        onboardingWindow.title = "Welcome to VoiceFlow"
        onboardingWindow.isReleasedWhenClosed = false
        onboardingWindow.delegate = self
        onboardingWindow.contentViewController = NSHostingController(
            rootView: OnboardingView(model: model)
        )
        onboardingWindow.center()
        self.window = onboardingWindow

        onboardingWindow.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func finish() {
        guard !isFinishing else { return }
        isFinishing = true
        onboardingModel = nil
        window?.close()
        window = nil
        isFinishing = false
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !isFinishing else { return true }
        // Closing the setup window is an explicit choice to skip setup. Persist
        // it so launch cannot unexpectedly reopen onboarding on every run.
        onboardingModel?.skipSetup()
        return true
    }
}

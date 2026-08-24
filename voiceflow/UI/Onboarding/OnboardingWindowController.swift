//
//  OnboardingWindowController.swift
//  VoiceFlow
//
//  First-launch onboarding window lifecycle.
//

import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSWindowController {
    static let shared = OnboardingWindowController()

    private static let contentSize = NSSize(width: 600, height: 520)
    private var onboardingModel: OnboardingModel?

    private init() {
        super.init(window: nil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func showIfNeeded(userDefaults: UserDefaults = .standard) {
        guard !userDefaults.bool(forKey: VoiceFlowOnboardingDefaults.completedKey) else { return }
        show(userDefaults: userDefaults)
    }

    func show(userDefaults: UserDefaults = .standard) {
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
        onboardingWindow.contentViewController = NSHostingController(
            rootView: OnboardingView(model: model)
        )
        onboardingWindow.center()
        self.window = onboardingWindow

        onboardingWindow.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func finish() {
        window?.close()
        onboardingModel = nil
    }
}

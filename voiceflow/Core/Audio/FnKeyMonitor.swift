//
//  FnKeyMonitor.swift
//  VoiceFlow
//
//  Created by Dhananjay Singh on 22/08/26.
//

import AppKit

/// Detects a sustained Fn press using the global flags-changed monitor.
///
/// `NSEvent` global monitoring is used here because the Fn modifier is exposed
/// through `NSEvent.ModifierFlags.function` on the supported macOS targets.
/// The callback is delivered only after the hold threshold; a short tap is
/// cancelled on release and does not activate recording.
final class FnKeyMonitor {
    var onFnKeyDown: (() -> Void)?
    var onFnKeyUp: (() -> Void)?

    private let holdThreshold: TimeInterval
    private var eventMonitor: Any?
    private var holdWorkItem: DispatchWorkItem?
    private var isFnPressed = false
    private var didEmitKeyDown = false

    init(holdThreshold: TimeInterval = 0.25) {
        self.holdThreshold = max(0, holdThreshold)
    }

    func start() {
        guard eventMonitor == nil else { return }

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
    }

    func stop() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }

        holdWorkItem?.cancel()
        holdWorkItem = nil
        isFnPressed = false
        didEmitKeyDown = false
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        handleFnStateChanged(event.modifierFlags.contains(.function))
    }

    /// Test seam for flags-changed events; production callers should use the
    /// global NSEvent monitor installed by `start()`.
    func handleFlagsChangedForTesting(isPressed: Bool) {
        handleFnStateChanged(isPressed)
    }

    private func handleFnStateChanged(_ fnIsPressed: Bool) {
        if !isFnPressed && fnIsPressed {
            isFnPressed = true
            scheduleKeyDown()
        } else if isFnPressed && !fnIsPressed {
            isFnPressed = false
            holdWorkItem?.cancel()
            holdWorkItem = nil

            guard didEmitKeyDown else { return }
            didEmitKeyDown = false
            onFnKeyUp?()
        }
    }

    private func scheduleKeyDown() {
        holdWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isFnPressed else { return }
            self.didEmitKeyDown = true
            self.onFnKeyDown?()
        }

        holdWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + holdThreshold, execute: workItem)
    }
}

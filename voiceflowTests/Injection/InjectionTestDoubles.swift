//
//  InjectionTestDoubles.swift
//  VoiceFlowTests
//

import AppKit
@testable import voiceflow

final class TestKeyboardEventPoster: KeyboardEventPosting {
    var error: Error?
    private(set) var postedTexts: [String] = []
    private(set) var postedProcessIdentifiers: [pid_t] = []

    func post(text: String, to processIdentifier: pid_t) throws {
        if let error { throw error }
        postedTexts.append(text)
        postedProcessIdentifiers.append(processIdentifier)
    }
}

final class TestTextInjector: TextInjecting {
    var isAccessibilityPermissionGranted = true
    var error: Error?
    private(set) var requestPermissionCallCount = 0
    private(set) var injectedTexts: [(text: String, target: NSRunningApplication?)] = []

    func requestAccessibilityPermission() {
        requestPermissionCallCount += 1
    }

    func inject(text: String, into targetApp: NSRunningApplication?) throws {
        if let error { throw error }
        injectedTexts.append((text, targetApp))
    }
}

struct TestInjectionError: Error {}

final class RecordingCompletionSoundPlayer: CompletionSoundPlaying {
    private(set) var playedEffects: [CompletionSoundEffect] = []

    var playCount: Int {
        playedEffects.count
    }

    func playCompletionSound(effect: CompletionSoundEffect) {
        playedEffects.append(effect)
    }
}

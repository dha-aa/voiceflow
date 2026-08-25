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
    private(set) var preferredFrontmostSessionFlags: [Bool] = []

    func post(text: String, to processIdentifier: pid_t) throws {
        if let error { throw error }
        postedTexts.append(text)
        postedProcessIdentifiers.append(processIdentifier)
        preferredFrontmostSessionFlags.append(false)
    }

    func post(text: String, to processIdentifier: pid_t, preferFrontmostSession: Bool) throws {
        if let error { throw error }
        postedTexts.append(text)
        postedProcessIdentifiers.append(processIdentifier)
        preferredFrontmostSessionFlags.append(preferFrontmostSession)
    }
}

final class TestTextInjector: TextInjecting, TextInputAvailabilityChecking {
    var isAccessibilityPermissionGranted = true
    var hasFocusedTextInput = true
    var error: Error?
    private(set) var requestPermissionCallCount = 0
    private(set) var injectedTexts: [(text: String, target: NSRunningApplication?)] = []

    func requestAccessibilityPermission() {
        requestPermissionCallCount += 1
    }

    func hasTextInput(in targetApp: NSRunningApplication) -> Bool {
        hasFocusedTextInput
    }

    func inject(text: String, into targetApp: NSRunningApplication?) throws {
        if let error { throw error }
        injectedTexts.append((text, targetApp))
    }
}

struct TestInjectionError: Error {}

final class TestPasteboardClipboardWriter: ClipboardWriting {
    let pasteboard: NSPasteboard
    private(set) var copiedTexts: [String] = []

    init(pasteboard: NSPasteboard) {
        self.pasteboard = pasteboard
    }

    func copy(text: String) throws {
        copiedTexts.append(text)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

final class TestPasteCommandPoster: PasteCommandPosting {
    private(set) var postCount = 0
    private(set) var endOfLinePostCount = 0

    func postPasteCommand() throws {
        postCount += 1
    }

    func postEndOfLineCommand() throws {
        endOfLinePostCount += 1
    }
}

final class TestTerminalTextPaster: TerminalTextPasting {
    private(set) var pastedTexts: [String] = []
    var error: Error?

    func paste(text: String) throws {
        if let error { throw error }
        pastedTexts.append(text)
    }
}

final class TestClipboardWriter: ClipboardWriting {
    var error: Error?
    private(set) var copiedTexts: [String] = []

    func copy(text: String) throws {
        if let error { throw error }
        copiedTexts.append(text)
    }
}

final class RecordingCompletionSoundPlayer: CompletionSoundPlaying {
    private(set) var playedEffects: [CompletionSoundEffect] = []

    var playCount: Int {
        playedEffects.count
    }

    func playCompletionSound(effect: CompletionSoundEffect) {
        playedEffects.append(effect)
    }
}

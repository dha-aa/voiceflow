//
//  SpeechTranscriptionRouterTests.swift
//  VoiceFlowTests
//

import Foundation
import XCTest
@testable import voiceflow

@MainActor
final class SpeechTranscriptionRouterTests: XCTestCase {
    func test_settingsPersistSelectedEngine() {
        let defaults = UserDefaults(suiteName: "speech-engine-\(UUID().uuidString)")!
        let settings = SpeechRecognitionSettings(userDefaults: defaults)

        settings.selectEngine(.parakeet)

        XCTAssertEqual(settings.selectedEngine, .parakeet)
        XCTAssertEqual(defaults.string(forKey: "selectedSpeechEngine"), "parakeet")
    }

    func test_routerDispatchesToSelectedEngine() async throws {
        let defaults = UserDefaults(suiteName: "speech-router-\(UUID().uuidString)")!
        let settings = SpeechRecognitionSettings(userDefaults: defaults)
        let whisper = TestSpeechEngine(name: "WhisperKit", text: "whisper")
        let parakeet = TestSpeechEngine(name: "Parakeet TDT v3", text: "parakeet")
        let router = SpeechTranscriptionRouter(
            settings: settings,
            whisperKitEngine: whisper,
            parakeetEngine: parakeet
        )
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("speech-router-\(UUID().uuidString).wav")
        try Data([0, 1, 2, 3]).write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        settings.selectEngine(.parakeet)
        let result = try await router.transcribe(audioURL: audioURL)

        XCTAssertEqual(result, "parakeet")
        XCTAssertEqual(router.displayName, "Parakeet TDT v3")
        XCTAssertEqual(whisper.transcribeCount, 0)
        XCTAssertEqual(parakeet.transcribeCount, 1)
        XCTAssertEqual(parakeet.selectionChangeCount, 1)
    }
}

@MainActor
private final class TestSpeechEngine: SpeechTranscriptionEngine {
    let displayName: String
    let text: String
    private(set) var transcribeCount = 0
    private(set) var selectionChangeCount = 0

    init(name: String, text: String) {
        self.displayName = name
        self.text = text
    }

    func prepare() async throws {}
    func waitUntilReady() async throws {}
    func preloadSelectedModel() {}

    func modelSelectionDidChange() {
        selectionChangeCount += 1
    }

    func transcribe(audioURL: URL) async throws -> String {
        transcribeCount += 1
        return text
    }
}

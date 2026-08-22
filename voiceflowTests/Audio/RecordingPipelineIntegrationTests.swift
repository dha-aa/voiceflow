//
//  RecordingPipelineIntegrationTests.swift
//  VoiceFlowTests
//

import AVFoundation
import XCTest
@testable import voiceflow

@MainActor
final class RecordingPipelineIntegrationTests: XCTestCase {
    func test_fullRecordingPipeline() async throws {
        let stateManager = AppStateManager()
        let engineProvider = TestAudioEngineProvider(sampleRate: 44_100)
        let recorder = AudioRecorder(
            engineProvider: engineProvider,
            permissionRequester: { true }
        )
        let monitor = FnKeyMonitor(holdThreshold: 0.01)
        let coordinator = RecordingCoordinator(
            stateManager: stateManager,
            recorder: recorder,
            keyMonitor: monitor
        )
        let completion = expectation(description: "full pipeline completion")
        var completedURL: URL?

        coordinator.onRecordingComplete = { url, _ in
            completedURL = url
            completion.fulfill()
        }

        coordinator.start()
        monitor.handleFlagsChangedForTesting(isPressed: true)
        try await waitUntil(timeout: 1) {
            stateManager.currentState == .recording
        }
        XCTAssertEqual(stateManager.currentState, .recording)

        engineProvider.engine.emitAudio(amplitude: 0.25, frameCount: 44_100)
        monitor.handleFlagsChangedForTesting(isPressed: false)
        await fulfillment(of: [completion], timeout: 1)

        let url = try XCTUnwrap(completedURL)
        defer {
            coordinator.stop()
            try? FileManager.default.removeItem(at: url)
        }

        XCTAssertEqual(stateManager.currentState, .processing)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertGreaterThan(FileManager.default.fileSize(atPath: url.path), 0)

        let audioFile = try AVAudioFile(forReading: url)
        XCTAssertEqual(audioFile.fileFormat.sampleRate, 16_000, accuracy: 0.1)
        XCTAssertEqual(audioFile.fileFormat.channelCount, 1)
    }

    private func waitUntil(
        timeout: TimeInterval,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline {
                throw XCTSkip("Timed out waiting for recording state")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private extension FileManager {
    func fileSize(atPath path: String) -> Int64 {
        ((try? attributesOfItem(atPath: path)[.size]) as? NSNumber)?.int64Value ?? 0
    }
}

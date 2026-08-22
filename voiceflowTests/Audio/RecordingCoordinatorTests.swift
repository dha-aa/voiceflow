//
//  RecordingCoordinatorTests.swift
//  VoiceFlowTests
//

import XCTest
@testable import voiceflow

@MainActor
final class RecordingCoordinatorTests: XCTestCase {
    func test_coordinator_waitsForModelReadinessBeforeRecording() async {
        let stateManager = AppStateManager()
        let recorder = TestRecording()
        let readiness = TestModelReadiness()
        let monitor = FnKeyMonitor(holdThreshold: 0.01)
        let coordinator = RecordingCoordinator(
            stateManager: stateManager,
            recorder: recorder,
            keyMonitor: monitor,
            modelReadiness: readiness
        )

        coordinator.start()
        monitor.handleFlagsChangedForTesting(isPressed: true)
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertTrue(readiness.waitStarted)
        XCTAssertEqual(stateManager.currentState, .preparingModel)
        XCTAssertEqual(recorder.startCount, 0)

        readiness.resume()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(stateManager.currentState, .recording)
        XCTAssertEqual(recorder.startCount, 1)
        coordinator.stop()
    }

    func test_coordinator_transitionsToRecording_onFnDown() async {
        let stateManager = AppStateManager()
        let recorder = TestRecording()
        let monitor = FnKeyMonitor(holdThreshold: 0.01)
        let coordinator = RecordingCoordinator(
            stateManager: stateManager,
            recorder: recorder,
            keyMonitor: monitor
        )

        coordinator.start()
        monitor.handleFlagsChangedForTesting(isPressed: true)
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(stateManager.currentState, .recording)
        XCTAssertEqual(recorder.startCount, 1)
        coordinator.stop()
    }

    func test_coordinator_transitionsToProcessing_onFnUp() async throws {
        let stateManager = AppStateManager()
        let recorder = TestRecording()
        recorder.stopURL = try makeTemporaryAudioURL()
        let monitor = FnKeyMonitor(holdThreshold: 0.01)
        let coordinator = RecordingCoordinator(
            stateManager: stateManager,
            recorder: recorder,
            keyMonitor: monitor
        )

        coordinator.start()
        monitor.handleFlagsChangedForTesting(isPressed: true)
        try? await Task.sleep(for: .milliseconds(50))
        monitor.handleFlagsChangedForTesting(isPressed: false)

        XCTAssertEqual(stateManager.currentState, .processing)
        XCTAssertEqual(recorder.stopCount, 1)
        coordinator.stop()
        try? FileManager.default.removeItem(at: recorder.stopURL!)
    }

    func test_coordinator_callsOnRecordingComplete_withAudioURL() async throws {
        let stateManager = AppStateManager()
        let recorder = TestRecording()
        recorder.stopURL = try makeTemporaryAudioURL()
        let monitor = FnKeyMonitor(holdThreshold: 0.01)
        let coordinator = RecordingCoordinator(
            stateManager: stateManager,
            recorder: recorder,
            keyMonitor: monitor
        )
        let completion = expectation(description: "recording completion")
        var receivedURL: URL?
        coordinator.onRecordingComplete = { url, _ in
            receivedURL = url
            completion.fulfill()
        }

        coordinator.start()
        monitor.handleFlagsChangedForTesting(isPressed: true)
        try? await Task.sleep(for: .milliseconds(50))
        monitor.handleFlagsChangedForTesting(isPressed: false)
        await fulfillment(of: [completion], timeout: 1)

        XCTAssertEqual(receivedURL, recorder.stopURL)
        coordinator.stop()
        try? FileManager.default.removeItem(at: recorder.stopURL!)
    }

    func test_coordinator_ignoresFnDown_whenStateIsNotIdle() async {
        let stateManager = AppStateManager()
        stateManager.transition(to: .processing)
        let recorder = TestRecording()
        let monitor = FnKeyMonitor(holdThreshold: 0.01)
        let coordinator = RecordingCoordinator(
            stateManager: stateManager,
            recorder: recorder,
            keyMonitor: monitor
        )

        coordinator.start()
        monitor.handleFlagsChangedForTesting(isPressed: true)
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(recorder.startCount, 0)
        XCTAssertEqual(stateManager.currentState, .processing)
        coordinator.stop()
    }

    func test_coordinator_releaseBeforePermissionCompletes_doesNotStartRecording() async {
        let stateManager = AppStateManager()
        let permissionGate = PermissionGate()
        let recorder = TestRecording()
        recorder.permissionProvider = { await permissionGate.wait() }
        let monitor = FnKeyMonitor(holdThreshold: 0.01)
        let coordinator = RecordingCoordinator(
            stateManager: stateManager,
            recorder: recorder,
            keyMonitor: monitor
        )

        coordinator.start()
        monitor.handleFlagsChangedForTesting(isPressed: true)
        try? await Task.sleep(for: .milliseconds(50))
        monitor.handleFlagsChangedForTesting(isPressed: false)
        permissionGate.resume(with: true)
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(recorder.startCount, 0)
        XCTAssertEqual(stateManager.currentState, .idle)
        coordinator.stop()
    }

    func test_coordinator_permissionDenied_transitionsToMicrophoneError() async {
        let stateManager = AppStateManager()
        let recorder = TestRecording()
        recorder.permissionGranted = false
        let monitor = FnKeyMonitor(holdThreshold: 0.01)
        let coordinator = RecordingCoordinator(
            stateManager: stateManager,
            recorder: recorder,
            keyMonitor: monitor
        )

        coordinator.start()
        monitor.handleFlagsChangedForTesting(isPressed: true)
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(stateManager.currentState, .error(.microphoneUnavailable))
        XCTAssertEqual(recorder.startCount, 0)
        coordinator.stop()
    }

    func test_coordinator_startFailure_transitionsToMicrophoneError() async {
        let stateManager = AppStateManager()
        let recorder = TestRecording()
        recorder.startError = AudioRecorder.RecorderError.engineCreationFailed
        let monitor = FnKeyMonitor(holdThreshold: 0.01)
        let coordinator = RecordingCoordinator(
            stateManager: stateManager,
            recorder: recorder,
            keyMonitor: monitor
        )

        coordinator.start()
        monitor.handleFlagsChangedForTesting(isPressed: true)
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(stateManager.currentState, .error(.microphoneUnavailable))
        coordinator.stop()
    }

    private func makeTemporaryAudioURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("coordinator-test-\(UUID().uuidString).wav")
        try Data([0x01]).write(to: url)
        return url
    }
}

@MainActor
private final class TestModelReadiness: ModelReadinessChecking {
    private var continuation: CheckedContinuation<Void, Error>?
    private(set) var waitStarted = false

    func waitUntilReady() async throws {
        waitStarted = true
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

private final class PermissionGate: @unchecked Sendable {
    private var continuation: CheckedContinuation<Bool, Never>?

    func wait() async -> Bool {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume(with value: Bool) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}

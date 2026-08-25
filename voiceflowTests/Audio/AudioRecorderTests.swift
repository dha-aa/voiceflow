//
//  AudioRecorderTests.swift
//  VoiceFlowTests
//

import AVFoundation
import XCTest
@testable import voiceflow

@MainActor
final class AudioRecorderTests: XCTestCase {
    func test_audioRecorder_initialState_notRecording() {
        let recorder = makeRecorder()

        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(recorder.audioLevel, 0)
    }

    func test_audioRecorder_permissionRequester_isUsed() async {
        var permissionCallCount = 0
        let recorder = AudioRecorder(
            engineProvider: TestAudioEngineProvider(),
            permissionRequester: {
                permissionCallCount += 1
                return false
            }
        )

        let granted = await recorder.requestPermission()

        XCTAssertFalse(granted)
        XCTAssertEqual(permissionCallCount, 1)
    }

    func test_audioRecorder_startRecording_setsIsRecording() throws {
        let recorder = makeRecorder()

        try recorder.startRecording()

        XCTAssertTrue(recorder.isRecording)
        XCTAssertNotNil(recorder.stopRecording())
    }

    func test_audioRecorder_stopRecording_setsIsRecordingFalse() throws {
        let recorder = makeRecorder()
        try recorder.startRecording()

        _ = recorder.stopRecording()

        XCTAssertFalse(recorder.isRecording)
    }

    func test_audioRecorder_writesRecordingInsideConfiguredAudioDirectory() throws {
        let audioDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("voiceflow-audio-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: audioDirectory) }
        let recorder = AudioRecorder(
            engineProvider: TestAudioEngineProvider(),
            audioDirectory: audioDirectory
        )

        try recorder.startRecording()
        let url = try XCTUnwrap(recorder.stopRecording())

        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL, audioDirectory.standardizedFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func test_audioRecorder_defaultDirectory_isVoiceFlowAudioFolder() {
        XCTAssertEqual(AudioRecorder.appAudioDirectory.lastPathComponent, "audio")
        XCTAssertTrue(AudioRecorder.appAudioDirectory.path.contains("dha-aa.voiceflow"))
    }

    func test_audioRecorder_stopRecording_returnsNonNilURLWithAudioData() throws {
        let provider = TestAudioEngineProvider()
        let recorder = AudioRecorder(engineProvider: provider)
        try recorder.startRecording()
        provider.engine.emitAudio(amplitude: 0.25)

        let url = try XCTUnwrap(recorder.stopRecording())
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertGreaterThan(FileManager.default.fileSize(atPath: url.path), 0)

        let audioFile = try AVAudioFile(forReading: url)
        XCTAssertEqual(audioFile.fileFormat.sampleRate, 16_000, accuracy: 0.1)
        XCTAssertEqual(audioFile.fileFormat.channelCount, 1)
        XCTAssertEqual(audioFile.fileFormat.commonFormat, .pcmFormatFloat32)
    }

    func test_audioRecorder_audioLevel_updatesWhileRecording() async throws {
        let provider = TestAudioEngineProvider()
        let recorder = AudioRecorder(engineProvider: provider)
        try recorder.startRecording()
        provider.engine.emitAudio(amplitude: 0.25)

        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertGreaterThan(recorder.audioLevel, 0)
        _ = recorder.stopRecording()
    }

    func test_audioRecorder_stopWithoutRecording_returnsNil() {
        let recorder = makeRecorder()

        XCTAssertNil(recorder.stopRecording())
    }

    private func makeRecorder() -> AudioRecorder {
        AudioRecorder(engineProvider: TestAudioEngineProvider())
    }
}

private extension FileManager {
    func fileSize(atPath path: String) -> Int64 {
        ((try? attributesOfItem(atPath: path)[.size]) as? NSNumber)?.int64Value ?? 0
    }
}

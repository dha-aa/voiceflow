//
//  AudioTestDoubles.swift
//  VoiceFlowTests
//

import AVFoundation
import Darwin
@testable import voiceflow

final class TestAudioEngineProvider: AudioEngineProviding {
    let engine: TestAudioEngine

    init(sampleRate: Double = 44_100, channels: AVAudioChannelCount = 1) {
        engine = TestAudioEngine(
            inputNode: TestAudioInputNode(sampleRate: sampleRate, channels: channels)
        )
    }

    func makeEngine() -> AudioEngine {
        engine
    }
}

final class TestAudioEngine: AudioEngine {
    let inputNode: AudioEngineInput
    private(set) var isStarted = false
    private(set) var isStopped = false

    init(inputNode: AudioEngineInput) {
        self.inputNode = inputNode
    }

    func start() throws {
        isStarted = true
    }

    func stop() {
        isStopped = true
    }

    func emitAudio(amplitude: Float = 0.25, frameCount: AVAudioFrameCount = 4_410) {
        (inputNode as? TestAudioInputNode)?.emitAudio(
            amplitude: amplitude,
            frameCount: frameCount
        )
    }
}

final class TestAudioInputNode: AudioEngineInput {
    private let format: AVAudioFormat
    private var tap: ((AVAudioPCMBuffer, AVAudioTime) -> Void)?

    init(sampleRate: Double, channels: AVAudioChannelCount) {
        format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false
        )!
    }

    func outputFormat(forBus bus: AVAudioNodeBus) -> AVAudioFormat {
        format
    }

    func installTap(
        onBus bus: AVAudioNodeBus,
        bufferSize: AVAudioFrameCount,
        format: AVAudioFormat?,
        block: @escaping (AVAudioPCMBuffer, AVAudioTime) -> Void
    ) {
        tap = block
    }

    func removeTap(onBus bus: AVAudioNodeBus) {
        tap = nil
    }

    func emitAudio(amplitude: Float, frameCount: AVAudioFrameCount) {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channelData = buffer.floatChannelData else {
            return
        }

        buffer.frameLength = frameCount
        for channel in 0..<Int(format.channelCount) {
            for frame in 0..<Int(frameCount) {
                channelData[channel][frame] = amplitude
            }
        }

        tap?(buffer, AVAudioTime(hostTime: mach_absolute_time()))
    }
}

final class TestRecording: AudioRecording {
    var permissionGranted = true
    var permissionProvider: (() async -> Bool)?
    var startError: Error?
    var isRecording = false
    var stopURL: URL?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func requestPermission() async -> Bool {
        if let permissionProvider {
            return await permissionProvider()
        }
        return permissionGranted
    }

    func startRecording() throws {
        if let startError { throw startError }
        startCount += 1
        isRecording = true
    }

    func stopRecording() -> URL? {
        stopCount += 1
        isRecording = false
        return stopURL
    }
}

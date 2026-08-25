//
//  AudioRecorder.swift
//  VoiceFlow
//
//  Created by Dhananjay Singh on 22/08/26.
//

import AVFoundation
import Foundation
import Observation
import OSLog

protocol AudioEngineInput: AnyObject {
    func outputFormat(forBus bus: AVAudioNodeBus) -> AVAudioFormat
    func installTap(
        onBus bus: AVAudioNodeBus,
        bufferSize: AVAudioFrameCount,
        format: AVAudioFormat?,
        block: @escaping (AVAudioPCMBuffer, AVAudioTime) -> Void
    )
    func removeTap(onBus bus: AVAudioNodeBus)
}

protocol AudioEngineProviding {
    func makeEngine() -> AudioEngine
}

protocol AudioEngine: AnyObject {
    var inputNode: AudioEngineInput { get }
    func start() throws
    func stop()
}

protocol AudioRecording: AnyObject {
    var isRecording: Bool { get }
    func requestPermission() async -> Bool
    func startRecording() throws
    func stopRecording() -> URL?
}

@Observable
final class AudioRecorder: AudioRecording {
    private(set) var audioLevel: Float = 0.0
    private(set) var isRecording: Bool = false

    private var audioEngine: AudioEngine?
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    private let engineProvider: AudioEngineProviding
    private let permissionRequester: () async -> Bool
    private let audioDirectory: URL
    private let metricsLock = NSLock()
    private var bufferCount = 0
    private var outputFrameCount: AVAudioFrameCount = 0
    private var bufferWriteErrorCount = 0
    private var recordingStartedAt: Date?

    // Audio format: 16,000 Hz, mono, PCM float32 (WhisperKit-compatible).
    private let sampleRate: Double = 16_000
    private let channels: AVAudioChannelCount = 1

    /// The persistent folder used for completed VoiceFlow recordings.
    /// In a sandboxed build, this resolves inside the app's Application Support container.
    static var appAudioDirectory: URL {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            preconditionFailure("VoiceFlow requires an Application Support directory")
        }
        guard let bundleIdentifier = Bundle.main.bundleIdentifier,
              !bundleIdentifier.isEmpty else {
            preconditionFailure("VoiceFlow requires a stable CFBundleIdentifier")
        }

        let directory = applicationSupport
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("audio", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    init(
        engineProvider: AudioEngineProviding = AVAudioEngineProvider(),
        permissionRequester: @escaping () async -> Bool = AudioRecorder.requestSystemPermission,
        audioDirectory: URL = AudioRecorder.appAudioDirectory
    ) {
        self.engineProvider = engineProvider
        self.permissionRequester = permissionRequester
        self.audioDirectory = audioDirectory.standardizedFileURL
    }

    func requestPermission() async -> Bool {
        VoiceFlowLog.audio.info("microphone_permission_request_started")
        let granted = await permissionRequester()
        if granted {
            VoiceFlowLog.audio.info("microphone_permission_granted")
        } else {
            VoiceFlowLog.audio.error("microphone_permission_denied")
        }
        return granted
    }

    func startRecording() throws {
        guard !isRecording else {
            VoiceFlowLog.audio.debug("recording_start_ignored reason=already_recording")
            return
        }

        resetMetrics()
        VoiceFlowLog.audio.info("recording_start_requested target_sample_rate=16000 target_channels=1 target_format=pcm_float32")

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false
        ) else {
            VoiceFlowLog.audio.error("recording_start_failed reason=target_format_creation_failed")
            throw RecorderError.invalidFormat
        }

        let engine = engineProvider.makeEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        let outputURL = audioDirectory
            .appendingPathComponent("recording_\(UUID().uuidString).wav")
        let audioID = VoiceFlowLog.audioIdentifier(for: outputURL)
        VoiceFlowLog.audio.info("recording_input_format recording_id=\(audioID, privacy: .public) sample_rate=\(inputFormat.sampleRate, privacy: .public) channels=\(inputFormat.channelCount, privacy: .public) common_format=\(inputFormat.commonFormat.rawValue, privacy: .public) converter_available=\(converter != nil, privacy: .public)")

        do {
            try FileManager.default.createDirectory(
                at: audioDirectory,
                withIntermediateDirectories: true
            )
            let file = try AVAudioFile(
                forWriting: outputURL,
                settings: targetFormat.settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )

            inputNode.installTap(onBus: 0, bufferSize: 1_024, format: inputFormat) { [weak self, weak file] buffer, _ in
                guard let self, let file else {
                    VoiceFlowLog.audio.error("audio_buffer_dropped reason=recorder_or_file_deallocated")
                    return
                }

                do {
                    let outputBuffer = try self.convert(
                        buffer,
                        using: converter,
                        targetFormat: targetFormat
                    )
                    try file.write(from: outputBuffer)
                    let metrics = self.recordWrittenBuffer(frameCount: outputBuffer.frameLength)
                    if metrics.bufferCount == 1 || metrics.bufferCount % 25 == 0 {
                        VoiceFlowLog.audio.debug("audio_buffer_written recording_id=\(audioID, privacy: .public) buffer_count=\(metrics.bufferCount, privacy: .public) output_frames=\(metrics.outputFrameCount, privacy: .public)")
                    }
                    self.updateAudioLevel(from: outputBuffer)
                } catch {
                    let errorCount = self.recordBufferWriteError()
                    VoiceFlowLog.audio.error("audio_buffer_write_failed recording_id=\(audioID, privacy: .public) error_count=\(errorCount, privacy: .public) error=\(String(describing: error), privacy: .public)")
                }
            }

            do {
                try engine.start()
            } catch {
                VoiceFlowLog.audio.error("recording_start_failed recording_id=\(audioID, privacy: .public) stage=engine_start error=\(String(describing: error), privacy: .public)")
                throw error
            }
            audioEngine = engine
            audioFile = file
            recordingURL = outputURL
            recordingStartedAt = Date()
            isRecording = true
            VoiceFlowLog.audio.info("recording_started recording_id=\(audioID, privacy: .public)")
        } catch {
            inputNode.removeTap(onBus: 0)
            audioEngine = nil
            audioFile = nil
            recordingURL = nil
            recordingStartedAt = nil
            try? FileManager.default.removeItem(at: outputURL)
            VoiceFlowLog.audio.error("recording_start_failed recording_id=\(audioID, privacy: .public) stage=file_or_tap_setup error=\(String(describing: error), privacy: .public)")
            throw error
        }
    }

    @discardableResult
    func stopRecording() -> URL? {
        guard let engine = audioEngine, isRecording else {
            VoiceFlowLog.audio.debug("recording_stop_ignored reason=not_recording")
            return nil
        }

        let completedURL = recordingURL
        let audioID = completedURL.map(VoiceFlowLog.audioIdentifier(for:)) ?? "unknown"
        let duration = recordingStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)

        // Releasing AVAudioFile flushes and closes the file on macOS 14, where
        // AVAudioFile.close() is not available in the deployment target SDK.
        audioFile = nil
        audioEngine = nil
        recordingURL = nil
        recordingStartedAt = nil
        isRecording = false
        audioLevel = 0.0

        let byteCount: Int64
        if let completedURL,
           let attributes = try? FileManager.default.attributesOfItem(atPath: completedURL.path),
           let size = attributes[.size] as? NSNumber {
            byteCount = size.int64Value
        } else {
            byteCount = 0
        }
        let metrics = snapshotMetrics()
        VoiceFlowLog.audio.info("recording_stopped recording_id=\(audioID, privacy: .public) duration_seconds=\(duration, privacy: .public) buffer_count=\(metrics.bufferCount, privacy: .public) output_frames=\(metrics.outputFrameCount, privacy: .public) write_error_count=\(metrics.writeErrorCount, privacy: .public) file_bytes=\(byteCount, privacy: .public)")

        return completedURL
    }

    private func convert(
        _ buffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter?,
        targetFormat: AVAudioFormat
    ) throws -> AVAudioPCMBuffer {
        guard let converter else { return buffer }

        let sampleRateRatio = targetFormat.sampleRate / buffer.format.sampleRate
        let outputCapacity = AVAudioFrameCount(
            ceil(Double(buffer.frameLength) * sampleRateRatio) + 1
        )
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputCapacity
        ) else {
            throw RecorderError.invalidFormat
        }

        var conversionError: NSError?
        var providedInput = false
        converter.convert(to: outputBuffer, error: &conversionError) { _, status in
            guard !providedInput else {
                status.pointee = .noDataNow
                return nil
            }

            providedInput = true
            status.pointee = .haveData
            return buffer
        }

        if let conversionError {
            throw conversionError
        }
        return outputBuffer
    }

    private func resetMetrics() {
        metricsLock.lock()
        bufferCount = 0
        outputFrameCount = 0
        bufferWriteErrorCount = 0
        metricsLock.unlock()
    }

    private func recordWrittenBuffer(frameCount: AVAudioFrameCount) -> (bufferCount: Int, outputFrameCount: AVAudioFrameCount) {
        metricsLock.lock()
        bufferCount += 1
        outputFrameCount += frameCount
        let metrics = (bufferCount, outputFrameCount)
        metricsLock.unlock()
        return metrics
    }

    private func recordBufferWriteError() -> Int {
        metricsLock.lock()
        bufferWriteErrorCount += 1
        let count = bufferWriteErrorCount
        metricsLock.unlock()
        return count
    }

    private func snapshotMetrics() -> (bufferCount: Int, outputFrameCount: AVAudioFrameCount, writeErrorCount: Int) {
        metricsLock.lock()
        let metrics = (bufferCount, outputFrameCount, bufferWriteErrorCount)
        metricsLock.unlock()
        return metrics
    }

    private func updateAudioLevel(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0], buffer.frameLength > 0 else {
            return
        }

        let frameLength = Int(buffer.frameLength)
        var sum: Float = 0
        for index in 0..<frameLength {
            sum += channelData[index] * channelData[index]
        }

        let rms = sqrt(sum / Float(frameLength))
        let normalizedLevel = min(max(rms * 10, 0), 1)

        Task { @MainActor [weak self] in
            self?.audioLevel = normalizedLevel
        }
    }

    private static func requestSystemPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    enum RecorderError: Error {
        case invalidFormat
        case microphoneUnavailable
        case engineCreationFailed
        case fileCreationFailed
    }
}

private final class AVAudioEngineProvider: AudioEngineProviding {
    func makeEngine() -> AudioEngine {
        AVAudioEngineAdapter()
    }
}

private final class AVAudioEngineAdapter: AudioEngine {
    private let engine: AVAudioEngine
    let inputNode: AudioEngineInput

    init() {
        let engine = AVAudioEngine()
        self.engine = engine
        self.inputNode = AVAudioInputAdapter(inputNode: engine.inputNode)
    }

    func start() throws {
        try engine.start()
    }

    func stop() {
        engine.stop()
    }
}

private final class AVAudioInputAdapter: AudioEngineInput {
    private let inputNode: AVAudioInputNode

    init(inputNode: AVAudioInputNode) {
        self.inputNode = inputNode
    }

    func outputFormat(forBus bus: AVAudioNodeBus) -> AVAudioFormat {
        inputNode.outputFormat(forBus: bus)
    }

    func installTap(
        onBus bus: AVAudioNodeBus,
        bufferSize: AVAudioFrameCount,
        format: AVAudioFormat?,
        block: @escaping (AVAudioPCMBuffer, AVAudioTime) -> Void
    ) {
        inputNode.installTap(onBus: bus, bufferSize: bufferSize, format: format, block: block)
    }

    func removeTap(onBus bus: AVAudioNodeBus) {
        inputNode.removeTap(onBus: bus)
    }
}

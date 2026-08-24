//
//  SpeechTranscriptionEngine.swift
//  VoiceFlow
//
//  Shared contract for local speech-to-text engines.
//

import Foundation
import Observation
import OSLog

@MainActor
protocol SpeechTranscriptionEngine: ModelReadinessChecking {
    var displayName: String { get }

    func prepare() async throws
    func preloadSelectedModel()
    func modelSelectionDidChange()
    func transcribe(audioURL: URL) async throws -> String
}

enum SpeechTranscriptionError: Error {
    case modelNotSelected
    case modelNotInstalled
    case modelFailedToLoad(underlying: Error)
    case audioFileNotFound
    case noAudioDetected
    case transcriptionFailed(underlying: Error)

    var category: String {
        switch self {
        case .modelNotSelected: "model_not_selected"
        case .modelNotInstalled: "model_not_installed"
        case .modelFailedToLoad: "model_load_failed"
        case .audioFileNotFound: "audio_file_missing"
        case .noAudioDetected: "no_audio_detected"
        case .transcriptionFailed: "transcription_runtime_failed"
        }
    }
}

@MainActor
final class SpeechTranscriptionRouter: SpeechTranscriptionEngine {
    private let settings: SpeechRecognitionSettings
    private let whisperKitEngine: SpeechTranscriptionEngine
    private let parakeetEngine: SpeechTranscriptionEngine

    init(
        settings: SpeechRecognitionSettings,
        whisperKitEngine: SpeechTranscriptionEngine,
        parakeetEngine: SpeechTranscriptionEngine
    ) {
        self.settings = settings
        self.whisperKitEngine = whisperKitEngine
        self.parakeetEngine = parakeetEngine
        settings.onEngineChanged = { [weak self] in
            self?.modelSelectionDidChange()
        }
    }

    var displayName: String {
        activeEngine.displayName
    }

    func prepare() async throws {
        try await activeEngine.prepare()
    }

    func waitUntilReady() async throws {
        try await activeEngine.waitUntilReady()
    }

    func preloadSelectedModel() {
        activeEngine.preloadSelectedModel()
    }

    func modelSelectionDidChange() {
        activeEngine.modelSelectionDidChange()
    }

    func transcribe(audioURL: URL) async throws -> String {
        try await activeEngine.transcribe(audioURL: audioURL)
    }

    private var activeEngine: SpeechTranscriptionEngine {
        switch settings.selectedEngine {
        case .whisperKit:
            whisperKitEngine
        case .parakeet:
            parakeetEngine
        }
    }
}

@MainActor
@Observable
final class SpeechRecognitionSettings {
    enum Engine: String, CaseIterable, Identifiable, Hashable {
        case whisperKit
        case parakeet

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .whisperKit: "WhisperKit"
            case .parakeet: "Parakeet TDT v3"
            }
        }
    }

    private static let selectedEngineKey = "selectedSpeechEngine"
    private let userDefaults: UserDefaults
    private(set) var selectedEngine: Engine
    var onEngineChanged: (() -> Void)?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let rawValue = userDefaults.string(forKey: Self.selectedEngineKey)
        self.selectedEngine = Engine(rawValue: rawValue ?? "") ?? .whisperKit
    }

    func selectEngine(_ engine: Engine) {
        guard selectedEngine != engine else { return }
        selectedEngine = engine
        userDefaults.set(engine.rawValue, forKey: Self.selectedEngineKey)
        VoiceFlowLog.model.info("speech_engine_selected engine=\(engine.rawValue, privacy: .public)")
        onEngineChanged?()
    }
}

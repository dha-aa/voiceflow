//
//  ApplicationComposition.swift
//  VoiceFlow
//
//  Owns the app-wide runtime graph and keeps lifecycle code separate from wiring.
//

import AppKit
import OSLog

@MainActor
final class ApplicationComposition {
    let stateManager: AppStateManager
    let modelManager: ModelManager
    let speechRecognitionSettings: SpeechRecognitionSettings
    let parakeetModelManager: ParakeetModelManager
    let snippetStore: SnippetStore
    let audioRetentionManager: AudioRetentionManager
    let aiSettingsService: AISettingsService
    let permissionManager: VoiceFlowPermissionManaging
    let downloadCoordinator: ModelDownloadCoordinator

    let menuBarController: MenuBarController
    let recordingCoordinator: RecordingCoordinator
    let transcriptionCoordinator: TranscriptionCoordinator
    let injectionCoordinator: InjectionCoordinator
    let overlayWindowController: OverlayWindowController

    private let transcriptionEngine: SpeechTranscriptionRouter
    private let whisperKitEngine: TranscriptionEngine
    private let parakeetEngine: ParakeetTranscriptionEngine
    private let audioRecorder: AudioRecorder

    init() {
        let stateManager = AppStateManager()
        let modelManager = ModelManager()
        let speechRecognitionSettings = SpeechRecognitionSettings()
        let parakeetModelManager = ParakeetModelManager()
        let snippetStore = SnippetStore()
        let audioRetentionManager = AudioRetentionManager()
        let aiSettingsService = AISettingsService()
        let permissionManager = SystemVoiceFlowPermissionManager()
        let downloadCoordinator = ModelDownloadCoordinator(modelManager: modelManager)
        let whisperKitEngine = TranscriptionEngine(modelManager: modelManager)
        let parakeetEngine = ParakeetTranscriptionEngine(modelManager: parakeetModelManager)
        let transcriptionEngine = SpeechTranscriptionRouter(
            settings: speechRecognitionSettings,
            whisperKitEngine: whisperKitEngine,
            parakeetEngine: parakeetEngine
        )
        let textInjector = TextInjector()
        let transcriptionCoordinator = TranscriptionCoordinator(
            stateManager: stateManager,
            engine: transcriptionEngine,
            processor: TextProcessor(),
            claudeProcessor: ClaudeCommandProcessor(selectedTextReader: textInjector),
            snippetStore: snippetStore
        )
        let injectionCoordinator = InjectionCoordinator(
            stateManager: stateManager,
            injector: textInjector
        )
        let audioRecorder = AudioRecorder()
        let recordingCoordinator = RecordingCoordinator(
            stateManager: stateManager,
            recorder: audioRecorder,
            keyMonitor: FnKeyMonitor(),
            modelReadiness: transcriptionEngine,
            selectedTextReader: textInjector
        )
        let overlayWindowController = OverlayWindowController(
            stateManager: stateManager,
            audioRecorder: audioRecorder
        )

        modelManager.modelLoadValidator = whisperKitEngine
        modelManager.onModelSelectionChanged = { [weak transcriptionEngine] _ in
            transcriptionEngine?.modelSelectionDidChange()
        }
        parakeetModelManager.onVariantChanged = { [weak parakeetEngine] in
            parakeetEngine?.modelSelectionDidChange()
        }
        parakeetModelManager.onModelAvailabilityChanged = { [weak parakeetEngine] in
            parakeetEngine?.preloadSelectedModel()
        }

        let menuBarController = MenuBarController(
            stateManager: stateManager,
            modelManager: modelManager,
            speechRecognitionSettings: speechRecognitionSettings,
            parakeetModelManager: parakeetModelManager,
            snippetStore: snippetStore,
            audioRetentionManager: audioRetentionManager,
            aiSettingsService: aiSettingsService,
            permissionManager: permissionManager,
            downloadCoordinator: downloadCoordinator
        )

        transcriptionCoordinator.onAIProcessingStarted = { [weak overlayWindowController] provider in
            Task { @MainActor in
                overlayWindowController?.showAIProcessing(for: provider)
            }
        }

        recordingCoordinator.onRecordingCompleteWithContext = { [transcriptionCoordinator, audioRetentionManager] audioURL, targetApplication, selectedText in
            Task { @MainActor in
                await transcriptionCoordinator.transcribe(
                    audioURL: audioURL,
                    targetApp: targetApplication,
                    selectedText: selectedText
                )
                audioRetentionManager.cleanupExpiredRecordings()
            }
        }

        transcriptionCoordinator.onTranscriptionComplete = { [injectionCoordinator] text, targetApplication in
            Task { @MainActor in
                await injectionCoordinator.inject(
                    text: text,
                    targetApp: targetApplication
                )
            }
        }

        self.stateManager = stateManager
        self.modelManager = modelManager
        self.speechRecognitionSettings = speechRecognitionSettings
        self.parakeetModelManager = parakeetModelManager
        self.snippetStore = snippetStore
        self.audioRetentionManager = audioRetentionManager
        self.aiSettingsService = aiSettingsService
        self.permissionManager = permissionManager
        self.downloadCoordinator = downloadCoordinator
        self.menuBarController = menuBarController
        self.recordingCoordinator = recordingCoordinator
        self.transcriptionCoordinator = transcriptionCoordinator
        self.injectionCoordinator = injectionCoordinator
        self.overlayWindowController = overlayWindowController
        self.transcriptionEngine = transcriptionEngine
        self.whisperKitEngine = whisperKitEngine
        self.parakeetEngine = parakeetEngine
        self.audioRecorder = audioRecorder
    }

    func start() {
        audioRetentionManager.startAutomaticCleanup()
        recordingCoordinator.start()
        overlayWindowController.start()
        refreshModelsInBackground()
    }

    func stop() {
        recordingCoordinator.stop()
        overlayWindowController.stop()
        audioRetentionManager.stopAutomaticCleanup()
    }

    private func refreshModelsInBackground() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await modelManager.refreshModels()
                parakeetModelManager.refresh()
                transcriptionEngine.preloadSelectedModel()
            } catch {
                VoiceFlowLog.model.error(
                    "model_catalog_refresh_failed error=\(String(describing: error), privacy: .public)"
                )
            }
        }
    }
}

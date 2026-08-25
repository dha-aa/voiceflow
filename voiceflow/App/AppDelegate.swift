//
//  AppDelegate.swift
//  VoiceFlow
//
//  Created by Dhananjay Singh on 22/08/26.
//

import AppKit
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let stateManager = AppStateManager()
    private var menuBarController: MenuBarController?
    private var recordingCoordinator: RecordingCoordinator?
    private var modelManager: ModelManager?
    private var speechRecognitionSettings: SpeechRecognitionSettings?
    private var parakeetModelManager: ParakeetModelManager?
    private var transcriptionCoordinator: TranscriptionCoordinator?
    private var injectionCoordinator: InjectionCoordinator?
    private var overlayWindowController: OverlayWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let modelManager = ModelManager()
        let speechRecognitionSettings = SpeechRecognitionSettings()
        let parakeetModelManager = ParakeetModelManager()
        let snippetStore = SnippetStore()
        VoiceFlowLog.model.info(
            "application_identity bundle_identifier=\(Bundle.main.bundleIdentifier ?? "<missing>", privacy: .public) application_support_directory=\(modelManager.downloadBase.deletingLastPathComponent().path, privacy: .public) models_root_directory=\(modelManager.downloadBase.path, privacy: .public)"
        )

        if ProcessInfo.processInfo.arguments.contains("--model-preflight") {
            if let modelIDIndex = ProcessInfo.processInfo.arguments.firstIndex(of: "--model-id"),
               ProcessInfo.processInfo.arguments.indices.contains(modelIDIndex + 1) {
                let modelID = ProcessInfo.processInfo.arguments[modelIDIndex + 1]
                modelManager.selectModel(id: modelID)
            }
            let output = modelManager.preflightSelectedModel()?.diagnosticDescription
                ?? ["VoiceFlow Model Preflight", "Selected Model: <none>", "", "RESULT: FAIL"].joined(separator: String(UnicodeScalar(10)))
            FileHandle.standardOutput.write(Data(output.utf8))
            NSApplication.shared.terminate(nil)
            return
        }

        menuBarController = MenuBarController(
            stateManager: stateManager,
            modelManager: modelManager,
            speechRecognitionSettings: speechRecognitionSettings,
            parakeetModelManager: parakeetModelManager,
            snippetStore: snippetStore
        )
        let whisperKitEngine = TranscriptionEngine(modelManager: modelManager)
        let parakeetEngine = ParakeetTranscriptionEngine(modelManager: parakeetModelManager)
        parakeetModelManager.onVariantChanged = { [weak parakeetEngine] in
            parakeetEngine?.modelSelectionDidChange()
        }
        parakeetModelManager.onModelAvailabilityChanged = { [weak parakeetEngine] in
            parakeetEngine?.preloadSelectedModel()
        }
        let transcriptionEngine = SpeechTranscriptionRouter(
            settings: speechRecognitionSettings,
            whisperKitEngine: whisperKitEngine,
            parakeetEngine: parakeetEngine
        )
        modelManager.modelLoadValidator = whisperKitEngine
        modelManager.onModelSelectionChanged = { [weak transcriptionEngine] _ in
            transcriptionEngine?.modelSelectionDidChange()
        }
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

        transcriptionCoordinator.onAIProcessingStarted = { [weak overlayWindowController] provider in
            Task { @MainActor in
                overlayWindowController?.showAIProcessing(for: provider)
            }
        }

        recordingCoordinator.onRecordingCompleteWithContext = { [transcriptionCoordinator] audioURL, targetApplication, selectedText in
            Task { @MainActor in
                await transcriptionCoordinator.transcribe(
                    audioURL: audioURL,
                    targetApp: targetApplication,
                    selectedText: selectedText
                )
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

        self.modelManager = modelManager
        self.speechRecognitionSettings = speechRecognitionSettings
        self.parakeetModelManager = parakeetModelManager
        self.transcriptionCoordinator = transcriptionCoordinator
        self.injectionCoordinator = injectionCoordinator
        self.recordingCoordinator = recordingCoordinator
        self.overlayWindowController = overlayWindowController
        recordingCoordinator.start()
        overlayWindowController.start()
        OnboardingWindowController.shared.showIfNeeded()

        Task { @MainActor [weak modelManager, weak transcriptionEngine] in
            do {
                try await modelManager?.refreshModels()
                parakeetModelManager.refresh()
                transcriptionEngine?.preloadSelectedModel()
            } catch {
                VoiceFlowLog.model.error("model_catalog_refresh_failed error=\(String(describing: error), privacy: .public)")
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        recordingCoordinator?.stop()
        overlayWindowController?.stop()
        recordingCoordinator = nil
        transcriptionCoordinator = nil
        injectionCoordinator = nil
        modelManager = nil
        speechRecognitionSettings = nil
        parakeetModelManager = nil
        overlayWindowController = nil
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

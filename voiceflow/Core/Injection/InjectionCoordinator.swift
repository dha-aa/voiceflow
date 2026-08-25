//
//  InjectionCoordinator.swift
//  VoiceFlow
//

import AppKit
import OSLog
import Foundation

final class InjectionCoordinator {
    private let stateManager: AppStateManager
    private let injector: TextInjecting
    private let userDefaults: UserDefaults
    private let completionSoundPlayer: CompletionSoundPlaying
    private let clipboardWriter: ClipboardWriting

    init(
        stateManager: AppStateManager,
        injector: TextInjecting,
        userDefaults: UserDefaults = .standard,
        completionSoundPlayer: CompletionSoundPlaying = SystemCompletionSoundPlayer(),
        clipboardWriter: ClipboardWriting = SystemClipboardWriter()
    ) {
        self.stateManager = stateManager
        self.injector = injector
        self.userDefaults = userDefaults
        self.completionSoundPlayer = completionSoundPlayer
        self.clipboardWriter = clipboardWriter
    }

    func inject(text: String, targetApp: NSRunningApplication?) async {
        guard stateManager.currentState == .injecting else {
            VoiceFlowLog.pipeline.error("text_injection_ignored reason=state_not_injecting current_state=\(String(describing: self.stateManager.currentState), privacy: .public)")
            print("Ignoring injection request outside injecting state")
            return
        }

        VoiceFlowLog.pipeline.info("text_output_started target_application_present=\(targetApp != nil, privacy: .public) text_character_count=\(text.count, privacy: .public)")
        do {
            let shouldCopyToClipboard: Bool
            if let targetApp, injector.isAccessibilityPermissionGranted {
                let hasTextInput = (injector as? TextInputAvailabilityChecking)?.hasTextInput(in: targetApp) ?? true
                shouldCopyToClipboard = !hasTextInput
            } else {
                shouldCopyToClipboard = targetApp == nil
            }

            if shouldCopyToClipboard {
                try clipboardWriter.copy(text: text)
                VoiceFlowLog.pipeline.info("clipboard_copy_succeeded text_character_count=\(text.count, privacy: .public)")
            } else {
                try injector.inject(text: text, into: targetApp)
                VoiceFlowLog.pipeline.info("text_injection_succeeded target_application_present=true text_character_count=\(text.count, privacy: .public)")
            }

            if userDefaults.object(forKey: VoiceFlowSettingsDefaults.playCompletionSoundKey) as? Bool ?? false {
                let storedEffect = userDefaults.string(forKey: VoiceFlowSettingsDefaults.completionSoundEffectKey)
                let effect = CompletionSoundEffect(rawValue: storedEffect ?? "") ?? .tink
                completionSoundPlayer.playCompletionSound(effect: effect)
                VoiceFlowLog.pipeline.info("completion_sound_played effect=\(effect.rawValue, privacy: .public)")
            }
            stateManager.transition(to: shouldCopyToClipboard ? .copiedToClipboard : .completed)
            VoiceFlowLog.pipeline.info("pipeline_completed target_application_present=\(targetApp != nil, privacy: .public) output_copied_to_clipboard=\(shouldCopyToClipboard, privacy: .public)")
            try? await Task.sleep(for: .milliseconds(400))
            guard stateManager.currentState == .completed || stateManager.currentState == .copiedToClipboard else { return }
            stateManager.transition(to: .idle)
            VoiceFlowLog.pipeline.info("pipeline_returned_to_idle reason=completed")
            print("State → idle")
        } catch let error as TextInjector.TextInjectionError {
            VoiceFlowLog.pipeline.error("text_output_failed target_application_present=\(targetApp != nil, privacy: .public) category=\(error.category, privacy: .public)")
            print("Text injection failed: \(error.localizedDescription)")
            if case .accessibilityPermissionDenied = error {
                stateManager.transition(to: .error(.accessibilityPermissionDenied))
            } else {
                stateManager.transition(to: .error(.injectionFailed))
            }
        } catch {
            VoiceFlowLog.pipeline.error("text_injection_failed target_application_present=\(targetApp != nil, privacy: .public) category=runtime error=\(String(describing: error), privacy: .public)")
            print("Text injection failed: \(error.localizedDescription)")
            stateManager.transition(to: .error(.injectionFailed))
        }
    }
}

enum CompletionSoundEffect: String, CaseIterable, Identifiable {
    case tink = "Tink"
    case pop = "Pop"
    case glass = "Glass"

    var id: String { rawValue }
}

protocol CompletionSoundPlaying {
    func playCompletionSound(effect: CompletionSoundEffect)
}

final class SystemCompletionSoundPlayer: CompletionSoundPlaying {
    func playCompletionSound(effect: CompletionSoundEffect) {
        guard let sound = NSSound(named: NSSound.Name(effect.rawValue)) else { return }
        sound.volume = 0.35
        sound.stop()
        sound.play()
    }
}


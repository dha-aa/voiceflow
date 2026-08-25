//
//  SettingsTests.swift
//  VoiceFlowTests
//

import Foundation
import XCTest
@testable import voiceflow

@MainActor
final class SettingsNavigationTests: XCTestCase {
    func test_speechEnginePickerUsesProviderNames() {
        XCTAssertEqual(SpeechRecognitionSettings.Engine.whisperKit.displayName, "WhisperKit")
        XCTAssertEqual(SpeechRecognitionSettings.Engine.parakeet.displayName, "FluidAudio")
    }

    func test_fluidAudioModelActionUsesDownloadInsteadOfRepair() {
        XCTAssertEqual(ModelsSettingsView.parakeetActionTitle(isLoading: false, isInstalled: false), "Download")
    }

    func test_fluidAudioHidesWhisperModels() {
        XCTAssertTrue(ModelsSettingsView.showsWhisperModels(for: .whisperKit))
        XCTAssertFalse(ModelsSettingsView.showsWhisperModels(for: .parakeet))
    }

    func test_fluidAudioDeleteActionIsAvailableForDownloadedModels() {
        XCTAssertTrue(ModelsSettingsView.showsFluidAudioDelete(isDownloaded: true))
        XCTAssertFalse(ModelsSettingsView.showsFluidAudioDelete(isDownloaded: false))
    }

    func test_settingsSidebarToggleUsesNaturalNavigationPlacement() {
        XCTAssertEqual(SettingsView.sidebarToggleTitle(isSidebarVisible: true), "Hide Sidebar")
        XCTAssertEqual(SettingsView.sidebarToggleTitle(isSidebarVisible: false), "Show Sidebar")
    }

    func test_fluidAudioCatalogContainsBothDownloadableVariants() {
        XCTAssertEqual(
            ParakeetModelManager.availableVariants,
            [.v3, .v2]
        )
    }

    func test_settingsDestinations_includeAllPanes() {
        let destinations = SettingsView.Destination.allCases

        XCTAssertEqual(destinations, [.general, .ai, .models, .snippets, .about])
        XCTAssertEqual(Set(destinations.map(\.title)), ["General", "AI", "Models", "Snippets", "About"])
        XCTAssertEqual(Set(destinations.map(\.systemImage)).count, 5)
    }

    func test_snippetsSettingsView_canBeConstructed() {
        _ = SnippetsSettingsView(store: SnippetStore())
        XCTAssertTrue(true)
    }

    func test_settingsView_canBeConstructed() {
        let manager = voiceflow.ModelManager(
            modelsDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("settings-navigation-\(UUID().uuidString)")
        )
        _ = SettingsView(
            modelManager: manager,
            downloadCoordinator: ModelDownloadCoordinator(modelManager: manager),
            speechRecognitionSettings: SpeechRecognitionSettings(userDefaults: UserDefaults(suiteName: "settings-engine-\(UUID().uuidString)")!),
            parakeetModelManager: ParakeetModelManager(),
            snippetStore: SnippetStore(),
            audioRetentionManager: AudioRetentionManager(),
            aiSettingsService: AISettingsService(),
            permissionManager: SystemVoiceFlowPermissionManager()
        )
        XCTAssertTrue(true)
    }

    func test_snippetStore_crudPersistsAcrossInstances() {
        let suiteName = "snippet-settings-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SnippetStore(userDefaults: defaults)
        let id = store.add(
            name: "My Email",
            trigger: "my email",
            value: "user@gmail.com"
        )
        XCTAssertEqual(store.snippets.count, 1)

        store.update(
            id: id,
            name: "Personal Email",
            trigger: "my personal email",
            value: "me@example.com"
        )
        XCTAssertEqual(store.snippets.first?.trigger, "my personal email")

        let restored = SnippetStore(userDefaults: defaults)
        XCTAssertEqual(restored.snippets.first?.value, "me@example.com")

        restored.delete(id: id)
        XCTAssertTrue(restored.snippets.isEmpty)
        XCTAssertTrue(SnippetStore(userDefaults: defaults).snippets.isEmpty)
    }
}

@MainActor
final class GeneralSettingsTests: XCTestCase {
    func test_audioRetentionPolicy_defaultIsNeverDelete() {
        let defaults = UserDefaults(suiteName: "audio-retention-default-\(UUID().uuidString)")!

        XCTAssertEqual(VoiceFlowSettingsDefaults.audioRetentionPolicy(in: defaults), .never)
    }

    func test_audioRetentionPolicy_persistsSelectedPolicy() {
        let defaults = UserDefaults(suiteName: "audio-retention-persist-\(UUID().uuidString)")!
        defaults.set(AudioRetentionPolicy.threeDays.rawValue, forKey: VoiceFlowSettingsDefaults.audioRetentionPolicyKey)

        XCTAssertEqual(VoiceFlowSettingsDefaults.audioRetentionPolicy(in: defaults), .threeDays)
    }

    func test_audioRetentionManager_deletesExpiredFilesAndKeepsRecentFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("audio-retention-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let oldURL = directory.appendingPathComponent("old.wav")
        let recentURL = directory.appendingPathComponent("recent.wav")
        try Data([1]).write(to: oldURL)
        try Data([2]).write(to: recentURL)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-4 * 24 * 60 * 60)], ofItemAtPath: oldURL.path)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-60)], ofItemAtPath: recentURL.path)

        let manager = AudioRetentionManager(
            audioDirectory: directory,
            policy: .threeDays,
            now: { now }
        )
        manager.cleanupExpiredRecordings()

        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recentURL.path))
    }

    func test_audioRetentionManager_deleteAllAudio_removesStoredWavFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("audio-delete-all-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let audioURL = directory.appendingPathComponent("recording.wav")
        let otherURL = directory.appendingPathComponent("keep.txt")
        try Data([1]).write(to: audioURL)
        try Data([2]).write(to: otherURL)

        let manager = AudioRetentionManager(audioDirectory: directory, policy: .never)
        manager.deleteAllAudio()

        XCTAssertFalse(FileManager.default.fileExists(atPath: audioURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: otherURL.path))
    }

    func test_showRecordingOverlay_defaultIsTrue() {
        let defaults = UserDefaults(suiteName: "general-settings-default-\(UUID().uuidString)")!

        XCTAssertTrue(VoiceFlowSettingsDefaults.showRecordingOverlay(in: defaults))
    }

    func test_playCompletionSound_defaultIsFalse() {
        let defaults = UserDefaults(suiteName: "completion-sound-default-\(UUID().uuidString)")!

        XCTAssertFalse(VoiceFlowSettingsDefaults.playCompletionSound(in: defaults))
    }

    func test_aiFeatures_defaultToOffOnFreshInstallation() {
        let defaults = UserDefaults(suiteName: "ai-features-default-\(UUID().uuidString)")!

        XCTAssertFalse(ClaudeSettings.isEnabled(in: defaults))
        XCTAssertFalse(ClaudeSettings.isGrammarFixEnabled(in: defaults))
        XCTAssertFalse(AISettings.alwaysUseAI(in: defaults))
        XCTAssertFalse(VoiceFlowSettingsDefaults.playCompletionSound(in: defaults))
    }

    func test_alwaysUseAI_preferencePersists() {
        let defaults = UserDefaults(suiteName: "always-ai-persist-\(UUID().uuidString)")!

        XCTAssertFalse(AISettings.alwaysUseAI(in: defaults))
        defaults.set(true, forKey: AISettings.alwaysUseAIKey)

        XCTAssertTrue(AISettings.alwaysUseAI(in: defaults))
    }

    func test_keychainRemove_deletesTheStoredProviderKey() throws {
        let service = "voiceflow-keychain-test-\(UUID().uuidString)"
        let store = KeychainAPIKeyStore(provider: .claude, service: service)
        try store.save("test-secret")
        XCTAssertEqual(try store.read(), "test-secret")

        try store.remove()

        XCTAssertNil(try store.read())
    }

    func test_playCompletionSound_persistsAfterToggle() {
        let defaults = UserDefaults(suiteName: "completion-sound-persist-\(UUID().uuidString)")!

        defaults.set(true, forKey: VoiceFlowSettingsDefaults.playCompletionSoundKey)

        XCTAssertTrue(VoiceFlowSettingsDefaults.playCompletionSound(in: defaults))
    }

    func test_completionSoundEffect_defaultsToTink() {
        let defaults = UserDefaults(suiteName: "completion-effect-default-\(UUID().uuidString)")!

        XCTAssertEqual(VoiceFlowSettingsDefaults.completionSoundEffect(in: defaults), .tink)
    }

    func test_completionSoundEffect_persistsSelectedEffect() {
        let defaults = UserDefaults(suiteName: "completion-effect-persist-\(UUID().uuidString)")!

        defaults.set(CompletionSoundEffect.glass.rawValue, forKey: VoiceFlowSettingsDefaults.completionSoundEffectKey)

        XCTAssertEqual(VoiceFlowSettingsDefaults.completionSoundEffect(in: defaults), .glass)
    }

    func test_showRecordingOverlay_persistsAfterToggle() {
        let defaults = UserDefaults(suiteName: "general-settings-persist-\(UUID().uuidString)")!

        defaults.set(false, forKey: VoiceFlowSettingsDefaults.showRecordingOverlayKey)

        XCTAssertFalse(VoiceFlowSettingsDefaults.showRecordingOverlay(in: defaults))
    }

    func test_generalSettingsView_canBeConstructed() {
        _ = GeneralSettingsView(
            permissionManager: SystemVoiceFlowPermissionManager(),
            audioRetentionManager: AudioRetentionManager()
        )
        XCTAssertTrue(true)
    }

    func test_aiSettings_defaultsToClaudeAndUsesPerProviderModelKeys() {
        let defaults = UserDefaults(suiteName: "ai-settings-default-\(UUID().uuidString)")!

        XCTAssertEqual(AISettings.selectedProvider(in: defaults), .claude)
        XCTAssertEqual(AISettings.selectedModel(for: .claude, in: defaults), ClaudeSettings.defaultModel)

        defaults.set(AIProvider.chatGPT.rawValue, forKey: AISettings.selectedProviderKey)
        defaults.set("gpt-test-model", forKey: AISettings.modelKey(for: .chatGPT))

        XCTAssertEqual(AISettings.selectedProvider(in: defaults), .chatGPT)
        XCTAssertEqual(AISettings.selectedModel(for: .chatGPT, in: defaults), "gpt-test-model")
    }

    func test_aiSettings_migratesLegacyClaudeModelValue() {
        let defaults = UserDefaults(suiteName: "ai-settings-migration-\(UUID().uuidString)")!
        defaults.set("legacy-claude-model", forKey: AISettings.legacyClaudeModelKey)

        XCTAssertEqual(AISettings.selectedModel(for: .claude, in: defaults), "legacy-claude-model")
    }

    func test_aiSettingsView_canBeConstructed() {
        _ = AISettingsView(settingsService: AISettingsService())
        XCTAssertTrue(true)
    }

    func test_claudeModelCatalog_decodesAndSortsModels() throws {
        let data = #"{"data":[{"id":"claude-z","display_name":"Zeta"},{"id":"claude-a","display_name":"Alpha"},{"id":"claude-no-name"}]}"#.data(using: .utf8)!

        let models = try LiveClaudeModelCatalogClient.decodeModels(from: data)

        XCTAssertEqual(models.map(\.id), ["claude-a", "claude-no-name", "claude-z"])
        XCTAssertEqual(models.first(where: { $0.id == "claude-no-name" })?.displayName, "claude-no-name")
    }
}

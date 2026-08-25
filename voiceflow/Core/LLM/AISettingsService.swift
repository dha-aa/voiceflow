//
//  AISettingsService.swift
//  VoiceFlow
//
//  Non-UI operations used by the AI Settings screen.
//

import Foundation

struct AISettingsService {
    private let keyStore: ClaudeAPIKeyStore
    private let modelCatalog: AIModelCatalogClient
    private let userDefaults: UserDefaults

    init(
        keyStore: ClaudeAPIKeyStore = KeychainClaudeAPIKeyStore(),
        modelCatalog: AIModelCatalogClient = LiveClaudeModelCatalogClient(),
        userDefaults: UserDefaults = .standard
    ) {
        self.keyStore = keyStore
        self.modelCatalog = modelCatalog
        self.userDefaults = userDefaults
    }

    func hasClaudeAPIKey() throws -> Bool {
        try keyStore.read() != nil
    }

    func saveClaudeAPIKey(_ apiKey: String) throws {
        try keyStore.save(apiKey)
    }

    func removeClaudeAPIKey() throws {
        try keyStore.remove()
    }

    func fetchClaudeModels() async throws -> [AIModel] {
        guard let apiKey = try keyStore.read(),
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClaudeCommandError.notConfigured
        }
        return try await modelCatalog.fetchModels(apiKey: apiKey)
    }

    func migrateLegacyClaudeModelIfNeeded() -> String? {
        guard userDefaults.string(forKey: AISettings.modelKey(for: .claude)) == nil,
              let legacyModel = userDefaults.string(forKey: AISettings.legacyClaudeModelKey),
              !legacyModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return legacyModel
    }
}

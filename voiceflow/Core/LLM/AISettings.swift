//
//  AISettings.swift
//  VoiceFlow
//
//  Provider-neutral AI settings and model discovery contracts.
//

import Foundation
import Security

/// AI providers represented by the settings architecture.
enum AIProvider: String, CaseIterable, Identifiable, Hashable {
    case claude
    case chatGPT

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude:
            "Claude"
        case .chatGPT:
            "ChatGPT"
        }
    }

    var systemImage: String {
        switch self {
        case .claude:
            "bubble.left.and.bubble.right"
        case .chatGPT:
            "sparkles"
        }
    }

    var isAvailable: Bool {
        switch self {
        case .claude:
            true
        case .chatGPT:
            false
        }
    }
}

struct AIModel: Identifiable, Hashable {
    let id: String
    let displayName: String

    init(id: String, displayName: String? = nil) {
        self.id = id
        self.displayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? displayName!
            : id
    }
}

protocol AIModelCatalogClient {
    func fetchModels(apiKey: String) async throws -> [AIModel]
}

enum AISettings {
    static let selectedProviderKey = "aiSelectedProvider"
    static let commandsEnabledKey = "claudeCommandsEnabled"
    static let commandPrefixKey = "aiCommandPrefix"
    static let legacyClaudeModelKey = "claudeModel"
    static let defaultCommandPrefix = "Claude"
    static let defaultClaudeModel = "claude-sonnet-5"

    static func modelKey(for provider: AIProvider) -> String {
        "aiModel.\(provider.rawValue)"
    }

    static func selectedProvider(in defaults: UserDefaults = .standard) -> AIProvider {
        guard let rawValue = defaults.string(forKey: selectedProviderKey),
              let provider = AIProvider(rawValue: rawValue) else {
            return .claude
        }
        return provider
    }

    static func selectedModel(
        for provider: AIProvider,
        in defaults: UserDefaults = .standard
    ) -> String {
        let current = defaults.string(forKey: modelKey(for: provider))
        let legacy = provider == .claude ? defaults.string(forKey: legacyClaudeModelKey) : nil
        let stored = (current ?? legacy)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stored.isEmpty ? defaultModel(for: provider) : stored
    }

    static func commandPrefix(in defaults: UserDefaults = .standard) -> String {
        let stored = defaults.string(forKey: commandPrefixKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stored.isEmpty ? defaultCommandPrefix : stored
    }

    static func defaultModel(for provider: AIProvider) -> String {
        switch provider {
        case .claude:
            defaultClaudeModel
        case .chatGPT:
            "gpt-4o-mini"
        }
    }
}

struct AICommand {
    let prompt: String

    static func parse(
        _ text: String,
        prefix: String = AISettings.defaultCommandPrefix
    ) -> AICommand? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty,
              !trimmedPrefix.isEmpty,
              let prefixRange = trimmedText.range(
                of: trimmedPrefix,
                options: [.anchored, .caseInsensitive]
              ) else {
            return nil
        }

        let remainder = trimmedText[prefixRange.upperBound...]
        if let firstCharacter = remainder.first,
           !firstCharacter.isWhitespace,
           !CharacterSet(charactersIn: ",:;.!?-_").contains(firstCharacter.unicodeScalars.first!) {
            return nil
        }

        let prompt = remainder.trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",:;.!?-_"))
        )
        return AICommand(prompt: prompt)
    }
}

/// Provider-neutral Keychain storage. Each provider has a separate account.
final class KeychainAPIKeyStore: ClaudeAPIKeyStore {
    private let service: String
    private let account: String

    init(provider: AIProvider, service: String = Bundle.main.bundleIdentifier ?? "dha-aa.voiceflow") {
        self.service = service
        switch provider {
        case .claude:
            account = "anthropic-api-key"
        case .chatGPT:
            account = "openai-api-key"
        }
    }

    func read() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            throw ClaudeKeychainError.readFailed(status)
        }
        return value
    }

    func save(_ apiKey: String) throws {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty,
              let data = trimmedKey.data(using: .utf8) else {
            return
        }
        try remove()
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw ClaudeKeychainError.saveFailed(status)
        }
    }

    func remove() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ClaudeKeychainError.removeFailed(status)
        }
    }
}

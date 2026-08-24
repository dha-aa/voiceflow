//
//  ClaudeClient.swift
//  VoiceFlow
//
//  Claude BYOK integration for explicit voice commands.
//

import Foundation
import OSLog
import Security

protocol ClaudeAPIClient {
    func complete(
        prompt: String,
        apiKey: String,
        model: String,
        systemPrompt: String?
    ) async throws -> String
}

protocol ClaudeAPIKeyStore {
    func read() throws -> String?
    func save(_ apiKey: String) throws
    func remove() throws
}

enum ClaudeKeychainError: Error {
    case readFailed(OSStatus)
    case saveFailed(OSStatus)
    case removeFailed(OSStatus)
}

final class KeychainClaudeAPIKeyStore: ClaudeAPIKeyStore {
    private let store: KeychainAPIKeyStore

    init(service: String = Bundle.main.bundleIdentifier ?? "dha-aa.voiceflow") {
        store = KeychainAPIKeyStore(provider: .claude, service: service)
    }

    func read() throws -> String? {
        try store.read()
    }

    func save(_ apiKey: String) throws {
        try store.save(apiKey)
    }

    func remove() throws {
        try store.remove()
    }
}

enum ClaudeSettings {
    static let enabledKey = AISettings.commandsEnabledKey
    static let grammarFixEnabledKey = AISettings.grammarFixEnabledKey
    static let modelKey = AISettings.modelKey(for: .claude)
    static let legacyModelKey = AISettings.legacyClaudeModelKey
    static let defaultModel = AISettings.defaultClaudeModel

    static let grammarCorrectionSystemPrompt = """
    You are a grammar and punctuation correction engine. Correct only the user's text. Preserve the original meaning, wording, tone, and information as much as possible. Fix grammar, spelling, capitalization, and punctuation only. Do not rewrite, paraphrase, summarize, explain, add information, remove information, add quotes, use Markdown, or include commentary. Return only the corrected text, ready for direct insertion.
    """

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? false
    }

    static func isGrammarFixEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: grammarFixEnabledKey) as? Bool ?? false
    }

    static func model(in defaults: UserDefaults = .standard) -> String {
        let currentValue = defaults.string(forKey: modelKey)
        let legacyValue = defaults.string(forKey: legacyModelKey)
        let value = (currentValue ?? legacyValue)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? defaultModel : value
    }
}

enum ClaudeCommandError: Error {
    case notConfigured
    case keychainUnavailable
    case requestFailed
    case emptyResponse
}

struct ClaudeCommandProcessor {
    private let apiClient: ClaudeAPIClient
    private let keyStore: ClaudeAPIKeyStore
    private let userDefaults: UserDefaults

    init(
        apiClient: ClaudeAPIClient = LiveClaudeAPIClient(),
        keyStore: ClaudeAPIKeyStore = KeychainClaudeAPIKeyStore(),
        userDefaults: UserDefaults = .standard
    ) {
        self.apiClient = apiClient
        self.keyStore = keyStore
        self.userDefaults = userDefaults
    }

    func requestedProvider(for text: String) -> AIProvider? {
        guard AISettings.selectedProvider(in: userDefaults) == .claude,
              requestedCommand(in: text) != nil || ClaudeSettings.isGrammarFixEnabled(in: userDefaults) else {
            return nil
        }
        return .claude
    }

    private func requestedCommand(in text: String) -> AICommand? {
        guard ClaudeSettings.isEnabled(in: userDefaults) else { return nil }
        return AICommand.parse(
            text,
            prefix: AISettings.commandPrefix(in: userDefaults)
        )
    }

    func processTranscribedText(_ text: String) async throws -> String? {
        guard AISettings.selectedProvider(in: userDefaults) == .claude else {
            return nil
        }

        // Explicit AI commands always win. Grammar correction must never edit
        // or reinterpret a command before its provider receives it.
        if let _ = requestedCommand(in: text) {
            return try await processIfRequested(text)
        }

        guard ClaudeSettings.isGrammarFixEnabled(in: userDefaults) else {
            return nil
        }
        return try await correctGrammar(text)
    }

    func processIfRequested(_ text: String) async throws -> String? {
        guard ClaudeSettings.isEnabled(in: userDefaults),
              AISettings.selectedProvider(in: userDefaults) == .claude,
              let command = AICommand.parse(
                text,
                prefix: AISettings.commandPrefix(in: userDefaults)
              ) else {
            return nil
        }
        let apiKey = try configuredAPIKey()
        guard !command.prompt.isEmpty else {
            throw ClaudeCommandError.emptyResponse
        }

        let model = AISettings.selectedModel(for: .claude, in: userDefaults)
        let startedAt = Date()
        VoiceFlowLog.llm.info("claude_request_started model_id=\(model, privacy: .public) prompt_character_count=\(command.prompt.count, privacy: .public)")
        do {
            let response = try await apiClient.complete(
                prompt: command.prompt,
                apiKey: apiKey,
                model: model,
                systemPrompt: nil
            )
            let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw ClaudeCommandError.emptyResponse
            }
            VoiceFlowLog.llm.info("claude_request_succeeded model_id=\(model, privacy: .public) response_character_count=\(trimmed.count, privacy: .public) duration_seconds=\(Date().timeIntervalSince(startedAt), privacy: .public)")
            return trimmed
        } catch let error as ClaudeCommandError {
            VoiceFlowLog.llm.error("claude_request_failed model_id=\(model, privacy: .public) category=\(String(describing: error), privacy: .public)")
            throw error
        } catch {
            VoiceFlowLog.llm.error("claude_request_failed model_id=\(model, privacy: .public) category=runtime duration_seconds=\(Date().timeIntervalSince(startedAt), privacy: .public)")
            throw ClaudeCommandError.requestFailed
        }
    }

    private func correctGrammar(_ text: String) async throws -> String {
        let apiKey = try configuredAPIKey()
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            throw ClaudeCommandError.emptyResponse
        }

        let model = AISettings.selectedModel(for: .claude, in: userDefaults)
        let startedAt = Date()
        VoiceFlowLog.llm.info("claude_grammar_request_started model_id=\(model, privacy: .public) input_character_count=\(normalizedText.count, privacy: .public)")
        do {
            let response = try await apiClient.complete(
                prompt: normalizedText,
                apiKey: apiKey,
                model: model,
                systemPrompt: ClaudeSettings.grammarCorrectionSystemPrompt
            )
            let correctedText = response.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !correctedText.isEmpty else {
                throw ClaudeCommandError.emptyResponse
            }
            VoiceFlowLog.llm.info("claude_grammar_request_succeeded model_id=\(model, privacy: .public) output_character_count=\(correctedText.count, privacy: .public) duration_seconds=\(Date().timeIntervalSince(startedAt), privacy: .public)")
            return correctedText
        } catch let error as ClaudeCommandError {
            VoiceFlowLog.llm.error("claude_grammar_request_failed model_id=\(model, privacy: .public) category=\(String(describing: error), privacy: .public)")
            throw error
        } catch {
            VoiceFlowLog.llm.error("claude_grammar_request_failed model_id=\(model, privacy: .public) category=runtime duration_seconds=\(Date().timeIntervalSince(startedAt), privacy: .public)")
            throw ClaudeCommandError.requestFailed
        }
    }

    private func configuredAPIKey() throws -> String {
        let apiKey: String?
        do {
            apiKey = try keyStore.read()
        } catch {
            throw ClaudeCommandError.keychainUnavailable
        }
        guard let apiKey,
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClaudeCommandError.notConfigured
        }
        return apiKey
    }
}

typealias ClaudeCommand = AICommand

private struct LiveClaudeAPIClient: ClaudeAPIClient {
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let anthropicVersion = "2023-06-01"

    private struct RequestBody: Encodable {
        let model: String
        let maxTokens: Int
        let system: String?
        let messages: [Message]

        enum CodingKeys: String, CodingKey {
            case model
            case maxTokens = "max_tokens"
            case system
            case messages
        }
    }

    private struct Message: Encodable {
        let role: String
        let content: String
    }

    private struct ResponseBody: Decodable {
        let content: [ContentBlock]
    }

    private struct ContentBlock: Decodable {
        let type: String
        let text: String?

        enum CodingKeys: String, CodingKey {
            case type
            case text
        }
    }

    func complete(
        prompt: String,
        apiKey: String,
        model: String,
        systemPrompt: String?
    ) async throws -> String {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            RequestBody(
                model: model,
                maxTokens: 1024,
                system: systemPrompt,
                messages: [Message(role: "user", content: prompt)]
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeCommandError.requestFailed
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ClaudeHTTPError.status(httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        let text = decoded.content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined(separator: "\n")
        guard !text.isEmpty else {
            throw ClaudeCommandError.emptyResponse
        }
        return text
    }
}

private enum ClaudeHTTPError: Error {
    case status(Int)
}

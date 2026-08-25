//
//  ClaudeTestSupport.swift
//  VoiceFlowTests
//
//  Shared test doubles for Claude and provider-neutral AI contracts.
//

import AppKit
@testable import voiceflow

final class TestClaudeAPIClient: ClaudeAPIClient {
    let response: String
    private(set) var callCount = 0
    private(set) var receivedPrompt: String?
    private(set) var receivedAPIKey: String?
    private(set) var receivedModel: String?
    private(set) var receivedSystemPrompt: String?

    init(response: String) {
        self.response = response
    }

    func complete(
        prompt: String,
        apiKey: String,
        model: String,
        systemPrompt: String?
    ) async throws -> String {
        callCount += 1
        receivedPrompt = prompt
        receivedAPIKey = apiKey
        receivedModel = model
        receivedSystemPrompt = systemPrompt
        return response
    }
}

final class TestAIProviderClient: AIProviderClient {
    let provider: AIProvider = .claude
    let response: String
    private(set) var request: AIProcessingRequest?

    init(response: String) {
        self.response = response
    }

    func complete(request: AIProcessingRequest, apiKey: String) async throws -> String {
        self.request = request
        return response
    }
}

final class TestFocusedTextSelectionReader: FocusedTextSelectionReading {
    let selectedText: String?

    init(selectedText: String?) {
        self.selectedText = selectedText
    }

    func selectedText(in targetApp: NSRunningApplication?) throws -> String? {
        selectedText
    }
}

final class TestClaudeAPIKeyStore: ClaudeAPIKeyStore {
    private(set) var storedAPIKey: String?

    init(apiKey: String?) {
        self.storedAPIKey = apiKey
    }

    func read() throws -> String? {
        storedAPIKey
    }

    func save(_ apiKey: String) throws {
        storedAPIKey = apiKey
    }

    func remove() throws {
        storedAPIKey = nil
    }
}

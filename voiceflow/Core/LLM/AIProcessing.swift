//
//  AIProcessing.swift
//  VoiceFlow
//
//  Provider-neutral contracts shared by Claude and future AI providers.
//

import Foundation

enum AIProcessingMode: Equatable {
    case command
    case grammarFix
}

struct AIScreenContext: Equatable {
    /// A future screen-context provider can supply a privacy-approved summary.
    /// The current app does not capture or populate screen context.
    let summary: String
}

struct AIProcessingRequest: Equatable {
    let text: String
    let mode: AIProcessingMode
    let model: String
    let screenContext: AIScreenContext?

    var systemPrompt: String {
        AIPromptBuilder.systemPrompt(for: mode, includesScreenContext: screenContext != nil)
    }
}

protocol AIProviderClient {
    var provider: AIProvider { get }
    func complete(request: AIProcessingRequest, apiKey: String) async throws -> String
}

enum AIPromptBuilder {
    static let command = "Return only the final content requested, ready to paste. Preserve the user’s intent. No explanations, filler, or unrequested information. Keep requested code, commands, lists, and line breaks valid."
    static let grammarFix = "Correct grammar, spelling, capitalization, punctuation, and obvious transcription errors only. Preserve meaning, wording, tone, and information. Return only the corrected text; no explanations, rewriting, Markdown, quotes, or added content."
    static let screenContext = "Use supplied screen context only to resolve references; do not describe it unless asked."

    static func systemPrompt(for mode: AIProcessingMode, includesScreenContext: Bool) -> String {
        let basePrompt: String
        switch mode {
        case .command:
            basePrompt = command
        case .grammarFix:
            basePrompt = grammarFix
        }
        return includesScreenContext ? "\(basePrompt) \(screenContext)" : basePrompt
    }
}

struct ClaudeAIProviderClient: AIProviderClient {
    let provider: AIProvider = .claude
    private let transport: ClaudeAPIClient

    init(transport: ClaudeAPIClient) {
        self.transport = transport
    }

    func complete(request: AIProcessingRequest, apiKey: String) async throws -> String {
        var prompt = request.text
        if let screenContext = request.screenContext {
            prompt += "\n\nScreen context:\n\(screenContext.summary)"
        }
        return try await transport.complete(
            prompt: prompt,
            apiKey: apiKey,
            model: request.model,
            systemPrompt: request.systemPrompt
        )
    }
}

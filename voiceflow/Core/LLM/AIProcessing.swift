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
    let selectedText: String?
    let screenContext: AIScreenContext?

    init(
        text: String,
        mode: AIProcessingMode,
        model: String,
        selectedText: String? = nil,
        screenContext: AIScreenContext? = nil
    ) {
        self.text = text
        self.mode = mode
        self.model = model
        self.selectedText = selectedText
        // A selection is the narrowest context and must suppress any broader
        // screen context before the request reaches a provider.
        self.screenContext = selectedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? nil
            : screenContext
    }

    var systemPrompt: String {
        AIPromptBuilder.systemPrompt(
            for: mode,
            includesScreenContext: screenContext != nil,
            includesSelectedText: selectedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        )
    }
}

protocol AIProviderClient {
    var provider: AIProvider { get }
    func complete(request: AIProcessingRequest, apiKey: String) async throws -> String
}

enum AIPromptBuilder {
    static let command = "Return only the final content requested, ready to paste. Preserve the user’s intent. No explanations, filler, or unrequested information. Keep requested code, commands, lists, and line breaks valid."
    static let grammarFix = "Correct grammar, spelling, capitalization, punctuation, and obvious transcription errors only. Preserve meaning, wording, tone, and information. Return only the corrected text; no explanations, rewriting, Markdown, quotes, or added content."
    static let selectionContext = "Use the selected text as the material to transform and the request as the instruction. Return only the final replacement text."
    static let screenContext = "Use supplied screen context only to resolve references; do not describe it unless asked."

    static func systemPrompt(
        for mode: AIProcessingMode,
        includesScreenContext: Bool,
        includesSelectedText: Bool = false
    ) -> String {
        let basePrompt: String
        switch mode {
        case .command:
            basePrompt = command
        case .grammarFix:
            basePrompt = grammarFix
        }

        var instructions = [basePrompt]
        if includesSelectedText {
            instructions.append(selectionContext)
        } else if includesScreenContext {
            instructions.append(screenContext)
        }
        return instructions.joined(separator: " ")
    }
}

struct ClaudeAIProviderClient: AIProviderClient {
    let provider: AIProvider = .claude
    private let transport: ClaudeAPIClient

    init(transport: ClaudeAPIClient) {
        self.transport = transport
    }

    func complete(request: AIProcessingRequest, apiKey: String) async throws -> String {
        let prompt: String
        if let selectedText = request.selectedText,
           !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            prompt = "Selected text:\n\(selectedText)\n\nInstruction:\n\(request.text)"
        } else if let screenContext = request.screenContext {
            prompt = "\(request.text)\n\nScreen context:\n\(screenContext.summary)"
        } else {
            prompt = request.text
        }

        return try await transport.complete(
            prompt: prompt,
            apiKey: apiKey,
            model: request.model,
            systemPrompt: request.systemPrompt
        )
    }
}

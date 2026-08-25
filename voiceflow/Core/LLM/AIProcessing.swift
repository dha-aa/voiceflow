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
    static let command = "Act as an intent-accurate text transformation assistant. Carefully infer what the user is trying to accomplish from natural, incomplete, imperfect, or speech-to-text input; do not require polished grammar or perfectly explicit instructions. Before producing the answer, determine the requested action, the intended audience and context, the type of output requested, and the format that best fulfills the request. Distinguish whether the user wants text written, rewritten, transformed, shortened, expanded, corrected, translated, explained, summarized, extracted, organized, listed, formatted, or converted. Follow the user’s requested operation rather than responding conversationally. When the request implies a structured output, produce that structure directly: for example, turn multiple things to remember into a clear numbered or bulleted note, preserve requested headings or fields, and keep code, commands, tables, lists, and line breaks valid. Resolve pronouns and references from supplied selected text or screen context when available, but do not invent missing facts. If information is missing, do not ask a follow-up question; make the best useful output possible from the available input and avoid unsupported claims. If selected text is supplied, treat it as the material to transform and the spoken request as the instruction; preserve its essential meaning, facts, and intent unless the user explicitly asks to change them. Preserve important names, numbers, links, code semantics, and user-specified constraints. Do not perform an unrelated task, add information, omit requested items, or change the requested level of detail. Return only the final output the user asked for, ready to paste into the current application. Do not include analysis, reasoning, intent labels, confirmations, conversational filler, a preamble, an explanation, quotation marks, or unrequested Markdown. Use Markdown only when the user requests it or when it is necessary to produce the requested structure or preserve the source format."
    static let grammarFix = "Correct grammar, spelling, capitalization, punctuation, sentence structure, and obvious speech-to-text errors. Preserve the same meaning, wording, tone, and information; make only necessary corrections. Return corrected text only. Do not answer, explain, rewrite, add, remove, quote, or use Markdown."
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

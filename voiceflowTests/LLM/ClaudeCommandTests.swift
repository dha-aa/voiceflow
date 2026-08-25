//
//  ClaudeClientTests.swift
//  VoiceFlowTests
//

import XCTest
@testable import voiceflow

@MainActor
final class ClaudeCommandTests: XCTestCase {
    func test_parserRecognizesClaudePrefixAndRemovesIt() {
        XCTAssertEqual(ClaudeCommand.parse("Claude, summarize this text")?.prompt, "summarize this text")
        XCTAssertEqual(ClaudeCommand.parse("claude: translate this")?.prompt, "translate this")
        XCTAssertNil(ClaudeCommand.parse("please summarize this"))
    }

    func test_parserSupportsCustomPhrasePrefixAndCaseInsensitiveMatching() {
        XCTAssertEqual(
            AICommand.parse("Ask Claude, explain this code", prefix: "Ask Claude")?.prompt,
            "explain this code"
        )
        XCTAssertEqual(
            AICommand.parse("@CLAUDE rewrite this", prefix: "@claude")?.prompt,
            "rewrite this"
        )
        XCTAssertNil(AICommand.parse("please Ask Claude, explain this", prefix: "Ask Claude"))
        XCTAssertNil(AICommand.parse("AIassistant explain this", prefix: "AI"))
    }

    func test_commandPrefixDefaultsAndPersists() {
        let defaults = UserDefaults(suiteName: "ai-prefix-\(UUID().uuidString)")!

        XCTAssertEqual(AISettings.commandPrefix(in: defaults), AISettings.defaultCommandPrefix)
        defaults.set("Jarvis", forKey: AISettings.commandPrefixKey)

        XCTAssertEqual(AISettings.commandPrefix(in: defaults), "Jarvis")
    }

    func test_processorDoesNothingForNormalDictation() async throws {
        let defaults = UserDefaults(suiteName: "claude-normal-\(UUID().uuidString)")!
        defaults.set(true, forKey: ClaudeSettings.enabledKey)
        let client = TestClaudeAPIClient(response: "should not be used")
        let keyStore = TestClaudeAPIKeyStore(apiKey: "test-key")
        let processor = ClaudeCommandProcessor(
            apiClient: client,
            keyStore: keyStore,
            userDefaults: defaults
        )

        let result = try await processor.processIfRequested("normal local dictation")

        XCTAssertNil(result)
        XCTAssertEqual(client.callCount, 0)
    }

    func test_processorForwardsOnlyTextAfterClaudePrefix() async throws {
        let defaults = UserDefaults(suiteName: "claude-forward-\(UUID().uuidString)")!
        defaults.set(true, forKey: ClaudeSettings.enabledKey)
        defaults.set("claude-sonnet-5", forKey: ClaudeSettings.modelKey)
        defaults.set("Ask Claude", forKey: AISettings.commandPrefixKey)
        let client = TestClaudeAPIClient(response: "Claude response")
        let keyStore = TestClaudeAPIKeyStore(apiKey: "test-key")
        let processor = ClaudeCommandProcessor(
            apiClient: client,
            keyStore: keyStore,
            userDefaults: defaults
        )

        let result = try await processor.processIfRequested("Ask Claude, make this concise")

        XCTAssertEqual(result, "Claude response")
        XCTAssertEqual(client.callCount, 1)
        XCTAssertEqual(client.receivedPrompt, "make this concise")
        XCTAssertEqual(client.receivedModel, "claude-sonnet-5")
        XCTAssertEqual(client.receivedAPIKey, "test-key")
    }

    func test_aiPrefixTakesPrecedenceWhenGrammarFixIsEnabled() async throws {
        let defaults = UserDefaults(suiteName: "claude-prefix-precedence-\(UUID().uuidString)")!
        defaults.set(true, forKey: ClaudeSettings.enabledKey)
        defaults.set(true, forKey: ClaudeSettings.grammarFixEnabledKey)
        let client = TestClaudeAPIClient(response: "Claude answer")
        let processor = ClaudeCommandProcessor(
            apiClient: client,
            keyStore: TestClaudeAPIKeyStore(apiKey: "test-key"),
            userDefaults: defaults
        )

        let result = try await processor.processTranscribedText("Claude explain how this code works")

        XCTAssertEqual(result, "Claude answer")
        XCTAssertEqual(client.callCount, 1)
        XCTAssertEqual(client.receivedPrompt, "explain how this code works")
        XCTAssertEqual(client.receivedSystemPrompt, ClaudeSettings.commandSystemPrompt)
    }

    func test_aiPrefixRoutesWithoutGrammarFix() async throws {
        let defaults = UserDefaults(suiteName: "claude-prefix-only-\(UUID().uuidString)")!
        defaults.set(true, forKey: ClaudeSettings.enabledKey)
        defaults.set(false, forKey: ClaudeSettings.grammarFixEnabledKey)
        let client = TestClaudeAPIClient(response: "Claude answer")
        let processor = ClaudeCommandProcessor(
            apiClient: client,
            keyStore: TestClaudeAPIKeyStore(apiKey: "test-key"),
            userDefaults: defaults
        )

        let result = try await processor.processTranscribedText("Claude explain this")

        XCTAssertEqual(result, "Claude answer")
        XCTAssertEqual(client.receivedPrompt, "explain this")
        XCTAssertEqual(client.receivedSystemPrompt, ClaudeSettings.commandSystemPrompt)
    }

    func test_grammarFixProcessesOnlyNonPrefixedSpeech() async throws {
        let defaults = UserDefaults(suiteName: "claude-grammar-only-\(UUID().uuidString)")!
        defaults.set(true, forKey: ClaudeSettings.grammarFixEnabledKey)
        let client = TestClaudeAPIClient(response: "I am going to the market tomorrow.")
        let processor = ClaudeCommandProcessor(
            apiClient: client,
            keyStore: TestClaudeAPIKeyStore(apiKey: "test-key"),
            userDefaults: defaults
        )

        let result = try await processor.processTranscribedText("i am going to market tomorrow")

        XCTAssertEqual(result, "I am going to the market tomorrow.")
        XCTAssertEqual(client.callCount, 1)
        XCTAssertEqual(client.receivedPrompt, "i am going to market tomorrow")
        XCTAssertEqual(client.receivedSystemPrompt, ClaudeSettings.grammarCorrectionSystemPrompt)
    }

    func test_normalSpeechBypassesClaudeWhenGrammarFixIsDisabled() async throws {
        let defaults = UserDefaults(suiteName: "claude-no-processing-\(UUID().uuidString)")!
        let client = TestClaudeAPIClient(response: "should not be used")
        let processor = ClaudeCommandProcessor(
            apiClient: client,
            keyStore: TestClaudeAPIKeyStore(apiKey: "test-key"),
            userDefaults: defaults
        )

        let result = try await processor.processTranscribedText("ordinary local dictation")

        XCTAssertNil(result)
        XCTAssertEqual(client.callCount, 0)
    }

    func test_claudeAdapterForwardsOptionalScreenContextThroughSharedRequest() async throws {
        let defaults = UserDefaults(suiteName: "claude-screen-context-\(UUID().uuidString)")!
        defaults.set(true, forKey: ClaudeSettings.enabledKey)
        let client = TestClaudeAPIClient(response: "Contextual answer")
        let processor = ClaudeCommandProcessor(
            apiClient: client,
            keyStore: TestClaudeAPIKeyStore(apiKey: "test-key"),
            userDefaults: defaults,
            screenContextProvider: {
                AIScreenContext(summary: "The user is viewing a code editor.")
            }
        )

        _ = try await processor.processTranscribedText("Claude explain this")

        XCTAssertEqual(
            client.receivedPrompt,
            "explain this\n\nScreen context:\nThe user is viewing a code editor."
        )
        XCTAssertTrue(client.receivedSystemPrompt?.contains(AIPromptBuilder.screenContext) == true)
    }

    func test_processorAcceptsProviderNeutralClientContract() async throws {
        let defaults = UserDefaults(suiteName: "provider-neutral-\(UUID().uuidString)")!
        defaults.set(true, forKey: ClaudeSettings.grammarFixEnabledKey)
        let client = TestAIProviderClient(response: "Corrected text")
        let processor = ClaudeCommandProcessor(
            providerClient: client,
            keyStore: TestClaudeAPIKeyStore(apiKey: "test-key"),
            userDefaults: defaults
        )

        let result = try await processor.processTranscribedText("i am ready")

        XCTAssertEqual(result, "Corrected text")
        XCTAssertEqual(client.request?.mode, .grammarFix)
        XCTAssertEqual(client.request?.text, "i am ready")
        XCTAssertEqual(client.request?.model, ClaudeSettings.defaultModel)
        XCTAssertEqual(client.request?.systemPrompt, AIPromptBuilder.grammarFix)
    }

    func test_processTranscribedTextAcceptsSelectionSnapshotWithoutTargetApp() async throws {
        let defaults = UserDefaults(suiteName: "claude-selection-snapshot-\(UUID().uuidString)")!
        defaults.set(true, forKey: ClaudeSettings.enabledKey)
        let client = TestAIProviderClient(response: "Replaced selection")
        let processor = ClaudeCommandProcessor(
            providerClient: client,
            keyStore: TestClaudeAPIKeyStore(apiKey: "test-key"),
            userDefaults: defaults
        )

        let result = try await processor.processTranscribedText(
            "Claude make this shorter",
            targetApp: nil,
            selectedText: "A long selected paragraph."
        )

        XCTAssertEqual(result, "Replaced selection")
        XCTAssertEqual(client.request?.selectedText, "A long selected paragraph.")
        XCTAssertEqual(client.request?.text, "make this shorter")
    }

    func test_commandPromptHandlesImperfectSpeechAndSelectionIntent() {
        let prompt = AIPromptBuilder.systemPrompt(
            for: .command,
            includesScreenContext: false,
            includesSelectedText: true
        )

        XCTAssertTrue(prompt.contains("imperfect"))
        XCTAssertTrue(prompt.contains("selected text"))
        XCTAssertTrue(prompt.contains("instruction"))
    }

    func test_commandPromptPrioritizesIntentAndRequestedOutputFormat() {
        let prompt = AIPromptBuilder.command.lowercased()

        XCTAssertTrue(prompt.contains("intent"))
        XCTAssertTrue(prompt.contains("format"))
        XCTAssertTrue(prompt.contains("structured"))
        XCTAssertTrue(prompt.contains("do not ask"))
        XCTAssertTrue(prompt.contains("final output"))
    }

    func test_alwaysUseAIProcessesUnprefixedSpeechAsACommand() async throws {
        let defaults = UserDefaults(suiteName: "claude-always-ai-\(UUID().uuidString)")!
        defaults.set(true, forKey: AISettings.alwaysUseAIKey)
        defaults.set(true, forKey: ClaudeSettings.grammarFixEnabledKey)
        let client = TestAIProviderClient(response: "1. Buy milk\\n2. Call John\\n3. Finish the report")
        let processor = ClaudeCommandProcessor(
            providerClient: client,
            keyStore: TestClaudeAPIKeyStore(apiKey: "test-key"),
            userDefaults: defaults
        )

        XCTAssertEqual(processor.requestedProvider(for: "take a note of three things"), .claude)
        let result = try await processor.processTranscribedText(
            "Take a note of three things: first, buy milk. Second, call John. Third, finish the report."
        )

        XCTAssertEqual(result, "1. Buy milk\\n2. Call John\\n3. Finish the report")
        XCTAssertEqual(client.request?.mode, .command)
        XCTAssertEqual(
            client.request?.text,
            "Take a note of three things: first, buy milk. Second, call John. Third, finish the report."
        )
    }

    func test_alwaysUseAIStillLetsExplicitPrefixWinOverGrammarFix() async throws {
        let defaults = UserDefaults(suiteName: "claude-always-prefix-\(UUID().uuidString)")!
        defaults.set(true, forKey: AISettings.commandsEnabledKey)
        defaults.set(true, forKey: AISettings.alwaysUseAIKey)
        defaults.set(true, forKey: ClaudeSettings.grammarFixEnabledKey)
        let client = TestAIProviderClient(response: "answer")
        let processor = ClaudeCommandProcessor(
            providerClient: client,
            keyStore: TestClaudeAPIKeyStore(apiKey: "test-key"),
            userDefaults: defaults
        )

        _ = try await processor.processTranscribedText("Claude explain this")

        XCTAssertEqual(client.request?.mode, .command)
        XCTAssertEqual(client.request?.text, "explain this")
    }

    func test_grammarPromptCorrectsSpeechToTextErrorsWithoutRewriting() {
        let prompt = AIPromptBuilder.grammarFix

        XCTAssertTrue(prompt.contains("speech-to-text"))
        XCTAssertTrue(prompt.contains("same meaning"))
        XCTAssertTrue(prompt.contains("Do not answer"))
    }

    func test_selectedTextIsForwardedAndScreenContextIsNotRequested() async throws {
        let defaults = UserDefaults(suiteName: "claude-selection-context-\(UUID().uuidString)")!
        defaults.set(true, forKey: ClaudeSettings.enabledKey)
        let client = TestAIProviderClient(response: "Shorter result")
        let selectionReader = TestFocusedTextSelectionReader(selectedText: "This is a very long paragraph.")
        var screenContextProviderCallCount = 0
        let processor = ClaudeCommandProcessor(
            providerClient: client,
            keyStore: TestClaudeAPIKeyStore(apiKey: "test-key"),
            userDefaults: defaults,
            screenContextProvider: {
                screenContextProviderCallCount += 1
                return AIScreenContext(summary: "The entire screen must not be used.")
            },
            selectedTextReader: selectionReader
        )

        let result = try await processor.processIfRequested("Claude make this shorter")

        XCTAssertEqual(result, "Shorter result")
        XCTAssertEqual(client.request?.text, "make this shorter")
        XCTAssertEqual(client.request?.selectedText, "This is a very long paragraph.")
        XCTAssertNil(client.request?.screenContext)
        XCTAssertTrue(client.request?.systemPrompt.contains(AIPromptBuilder.selectionContext) == true)
        XCTAssertEqual(screenContextProviderCallCount, 0)
    }

    func test_screenContextIsFallbackWhenNoTextIsSelected() async throws {
        let defaults = UserDefaults(suiteName: "claude-selection-fallback-\(UUID().uuidString)")!
        defaults.set(true, forKey: ClaudeSettings.enabledKey)
        let client = TestAIProviderClient(response: "Contextual result")
        let processor = ClaudeCommandProcessor(
            providerClient: client,
            keyStore: TestClaudeAPIKeyStore(apiKey: "test-key"),
            userDefaults: defaults,
            screenContextProvider: {
                AIScreenContext(summary: "The active app is a code editor.")
            },
            selectedTextReader: TestFocusedTextSelectionReader(selectedText: nil)
        )

        _ = try await processor.processIfRequested("Claude explain this")

        XCTAssertNil(client.request?.selectedText)
        XCTAssertEqual(client.request?.screenContext?.summary, "The active app is a code editor.")
        XCTAssertTrue(client.request?.systemPrompt.contains(AIPromptBuilder.screenContext) == true)
    }

    func test_processorRejectsClaudeCommandWithoutAPIKey() async {
        let defaults = UserDefaults(suiteName: "claude-no-key-\(UUID().uuidString)")!
        defaults.set(true, forKey: ClaudeSettings.enabledKey)
        let processor = ClaudeCommandProcessor(
            apiClient: TestClaudeAPIClient(response: "unused"),
            keyStore: TestClaudeAPIKeyStore(apiKey: nil),
            userDefaults: defaults
        )

        do {
            _ = try await processor.processIfRequested("Claude, do something")
            XCTFail("Expected missing API key error")
        } catch let error as ClaudeCommandError {
            guard case .notConfigured = error else {
                return XCTFail("Unexpected Claude error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

}

//
//  TextProcessorTests.swift
//  VoiceFlowTests
//

import XCTest
@testable import voiceflow

final class TextProcessorTests: XCTestCase {
    private let processor = TextProcessor()

    func test_textProcessor_trimsLeadingTrailingWhitespace() {
        XCTAssertEqual(processor.process("  hello world  "), "hello world")
    }

    func test_textProcessor_collapsesMultipleSpaces() {
        XCTAssertEqual(processor.process("hello   world"), "hello world")
    }

    func test_textProcessor_removesBlankAudioArtifact() {
        XCTAssertEqual(processor.process("[BLANK_AUDIO]"), "")
    }

    func test_textProcessor_removesInaudibleMarker() {
        XCTAssertEqual(processor.process("hello (inaudible) world"), "hello world")
    }

    func test_textProcessor_preservesNormalText() {
        let text = "The quick brown fox jumps over the lazy dog."
        XCTAssertEqual(processor.process(text), text)
    }

    func test_textProcessor_handlesEmptyString() {
        XCTAssertEqual(processor.process(""), "")
    }

    func test_snippetStore_expandsTriggerInsideNaturalSentenceCaseInsensitively() {
        let store = SnippetStore(snippets: [
            Snippet(name: "My Email", trigger: "my email", value: "user@gmail.com")
        ])

        XCTAssertEqual(
            store.expand("You can contact me at my email address."),
            "You can contact me at user@gmail.com address."
        )
    }

    func test_snippetStore_matchesWholeTriggerWordsOnly() {
        let store = SnippetStore(snippets: [
            Snippet(name: "My Email", trigger: "my email", value: "user@gmail.com")
        ])

        XCTAssertEqual(store.expand("my email"), "user@gmail.com")
        XCTAssertEqual(store.expand("my emails are private"), "my emails are private")
    }

    func test_snippetStore_prefersLongerOverlappingTrigger() {
        let store = SnippetStore(snippets: [
            Snippet(name: "Email", trigger: "email", value: "short@example.com"),
            Snippet(name: "My Email", trigger: "my email", value: "user@gmail.com")
        ])

        XCTAssertEqual(store.expand("Please use my email"), "Please use user@gmail.com")
    }
}

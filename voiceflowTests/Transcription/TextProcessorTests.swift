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
}

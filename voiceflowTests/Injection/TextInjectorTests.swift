//
//  TextInjectorTests.swift
//  VoiceFlowTests
//

import AppKit
import XCTest
@testable import voiceflow

@MainActor
final class TextInjectorTests: XCTestCase {
    func test_textInjector_usesFrontmostKeyboardEvents_forTerminalFamily() {
        XCTAssertTrue(TextInjector.usesFrontmostKeyboardEvents(for: "com.apple.Terminal"))
        XCTAssertTrue(TextInjector.usesFrontmostKeyboardEvents(for: "com.googlecode.iterm2"))
        XCTAssertFalse(TextInjector.usesFrontmostKeyboardEvents(for: "com.apple.TextEdit"))
        XCTAssertFalse(TextInjector.usesFrontmostKeyboardEvents(for: nil))
    }

    func test_textInjector_usesClipboardPasteFallback_onlyForFrontmostNonTerminalTargets() {
        XCTAssertTrue(
            TextInjector.shouldUseClipboardPasteFallback(
                isTerminalTarget: false,
                isFrontmostTarget: true
            )
        )
        XCTAssertFalse(
            TextInjector.shouldUseClipboardPasteFallback(
                isTerminalTarget: true,
                isFrontmostTarget: true
            )
        )
        XCTAssertFalse(
            TextInjector.shouldUseClipboardPasteFallback(
                isTerminalTarget: false,
                isFrontmostTarget: false
            )
        )
    }

    func test_textInjector_usesPasteWriter_forTerminalTarget() throws {
        let poster = TestKeyboardEventPoster()
        let paster = TestTextPaster()
        let injector = TextInjector(
            keyboardEventPoster: poster,
            textPaster: paster,
            permissionChecker: { true },
            bundleIdentifierProvider: { _ in "com.apple.Terminal" },
            frontmostApplicationProvider: { _ in true }
        )
        let targetApp = try XCTUnwrap(
            NSRunningApplication(processIdentifier: ProcessInfo.processInfo.processIdentifier)
        )

        try injector.inject(text: "echo hello", into: targetApp)

        XCTAssertEqual(paster.pastedTexts, ["echo hello"])
        XCTAssertEqual(paster.moveCaretToEndOfLineFlags, [true])
        XCTAssertTrue(poster.postedTexts.isEmpty)
    }

    func test_textInjector_usesClipboardPasteFallback_forFrontmostNonTerminalTarget() throws {
        let poster = TestKeyboardEventPoster()
        let paster = TestTextPaster()
        let injector = TextInjector(
            keyboardEventPoster: poster,
            textPaster: paster,
            permissionChecker: { true },
            bundleIdentifierProvider: { _ in "com.apple.TextEdit" },
            frontmostApplicationProvider: { _ in true }
        )
        let targetApp = try XCTUnwrap(
            NSRunningApplication(processIdentifier: ProcessInfo.processInfo.processIdentifier)
        )

        try injector.inject(text: "plain text", into: targetApp)

        XCTAssertEqual(paster.pastedTexts, ["plain text"])
        XCTAssertEqual(paster.moveCaretToEndOfLineFlags, [false])
        XCTAssertTrue(poster.postedTexts.isEmpty)
    }

    func test_textInjector_usesKeyboardEvents_forNonFrontmostTerminalTarget() throws {
        let poster = TestKeyboardEventPoster()
        let paster = TestTextPaster()
        let injector = TextInjector(
            keyboardEventPoster: poster,
            textPaster: paster,
            permissionChecker: { true },
            bundleIdentifierProvider: { _ in "com.apple.Terminal" },
            frontmostApplicationProvider: { _ in false }
        )
        let targetApp = try XCTUnwrap(
            NSRunningApplication(processIdentifier: ProcessInfo.processInfo.processIdentifier)
        )

        try injector.inject(text: "terminal text", into: targetApp)

        XCTAssertTrue(paster.pastedTexts.isEmpty)
        XCTAssertEqual(poster.postedTexts, ["terminal text"])
        XCTAssertEqual(poster.preferredFrontmostSessionFlags, [false])
    }

    func test_terminalPasteMovesInputToEndOfLine() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("VoiceFlowTerminalEndTests"))
        let clipboardWriter = TestPasteboardClipboardWriter(pasteboard: pasteboard)
        let commandPoster = TestPasteCommandPoster()
        let paster = SystemTextPaster(
            clipboardWriter: clipboardWriter,
            pasteCommandPoster: commandPoster,
            pasteboard: pasteboard,
            restoreDelay: 0
        )

        try paster.paste(text: "terminal output", moveCaretToEndOfLine: true)

        XCTAssertEqual(commandPoster.postCount, 1)
        XCTAssertEqual(commandPoster.endOfLinePostCount, 1)
    }

    func test_textInjector_placesCaretAtEndOfUpdatedText() {
        XCTAssertEqual(
            TextInjector.endCaretLocation(
                existingText: "before after",
                selectedRange: NSRange(location: 0, length: 6),
                replacement: "replacement"
            ),
            ("replacement after" as NSString).length
        )
    }

    func test_terminalPasteRestoresPreviousClipboardContents() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("VoiceFlowTerminalPasteTests"))
        pasteboard.clearContents()
        pasteboard.setString("previous clipboard", forType: .string)
        let clipboardWriter = TestPasteboardClipboardWriter(pasteboard: pasteboard)
        let commandPoster = TestPasteCommandPoster()
        let paster = SystemTextPaster(
            clipboardWriter: clipboardWriter,
            pasteCommandPoster: commandPoster,
            pasteboard: pasteboard,
            restoreDelay: 0
        )

        try paster.paste(text: "terminal output")

        XCTAssertEqual(clipboardWriter.copiedTexts, ["terminal output"])
        XCTAssertEqual(commandPoster.postCount, 1)
        XCTAssertEqual(commandPoster.endOfLinePostCount, 0)
        XCTAssertEqual(pasteboard.string(forType: .string), "previous clipboard")
        pasteboard.clearContents()
    }

    func test_textInjector_injectsText_intoFocusedApp() throws {
        let poster = TestKeyboardEventPoster()
        let injector = TextInjector(
            keyboardEventPoster: poster,
            permissionChecker: { true },
            frontmostApplicationProvider: { _ in false }
        )
        let targetApp = try XCTUnwrap(
            NSRunningApplication(processIdentifier: ProcessInfo.processInfo.processIdentifier)
        )

        try injector.inject(text: "hello world", into: targetApp)

        XCTAssertEqual(poster.postedTexts, ["hello world"])
        XCTAssertEqual(
            poster.postedProcessIdentifiers,
            [ProcessInfo.processInfo.processIdentifier]
        )
    }

    func test_textInjector_rejects_emptyText() throws {
        let poster = TestKeyboardEventPoster()
        let injector = TextInjector(keyboardEventPoster: poster)
        let targetApp = try XCTUnwrap(
            NSRunningApplication(processIdentifier: ProcessInfo.processInfo.processIdentifier)
        )

        XCTAssertThrowsError(try injector.inject(text: "", into: targetApp)) { error in
            guard case .emptyText = error as? TextInjector.TextInjectionError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertTrue(poster.postedTexts.isEmpty)
    }

    func test_textInjector_requiresAccessibilityPermission() throws {
        let poster = TestKeyboardEventPoster()
        var requestCount = 0
        let injector = TextInjector(
            keyboardEventPoster: poster,
            permissionChecker: { false },
            permissionRequester: { requestCount += 1 }
        )
        let targetApp = try XCTUnwrap(
            NSRunningApplication(processIdentifier: ProcessInfo.processInfo.processIdentifier)
        )

        XCTAssertThrowsError(try injector.inject(text: "hello", into: targetApp)) { error in
            guard case .accessibilityPermissionDenied = error as? TextInjector.TextInjectionError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(requestCount, 1)
        XCTAssertTrue(poster.postedTexts.isEmpty)
    }

    func test_textInjector_handlesNilTargetApp() {
        let injector = TextInjector(keyboardEventPoster: TestKeyboardEventPoster())

        XCTAssertThrowsError(try injector.inject(text: "hello", into: nil)) { error in
            guard case .targetApplicationUnavailable = error as? TextInjector.TextInjectionError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func test_textInjector_extractsSelectedTextFromValueAndUTF16Range() {
        let value = "before 👋 selected text after"
        let selectedText = TextInjector.selectedText(
            from: value,
            range: NSRange(location: 10, length: 13)
        )

        XCTAssertEqual(selectedText, "selected text")
    }

    func test_textInjector_reportsError_onFailure() throws {
        let poster = TestKeyboardEventPoster()
        poster.error = TestInjectionError()
        let injector = TextInjector(
            keyboardEventPoster: poster,
            permissionChecker: { true },
            frontmostApplicationProvider: { _ in false }
        )
        let targetApp = try XCTUnwrap(
            NSRunningApplication(processIdentifier: ProcessInfo.processInfo.processIdentifier)
        )

        XCTAssertThrowsError(try injector.inject(text: "hello", into: targetApp))
    }
}

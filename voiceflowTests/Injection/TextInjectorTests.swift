//
//  TextInjectorTests.swift
//  VoiceFlowTests
//

import AppKit
import XCTest
@testable import voiceflow

@MainActor
final class TextInjectorTests: XCTestCase {
    func test_textInjector_injectsText_intoFocusedApp() throws {
        let poster = TestKeyboardEventPoster()
        let injector = TextInjector(
            keyboardEventPoster: poster,
            permissionChecker: { true }
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

    func test_textInjector_reportsError_onFailure() throws {
        let poster = TestKeyboardEventPoster()
        poster.error = TestInjectionError()
        let injector = TextInjector(
            keyboardEventPoster: poster,
            permissionChecker: { true }
        )
        let targetApp = try XCTUnwrap(
            NSRunningApplication(processIdentifier: ProcessInfo.processInfo.processIdentifier)
        )

        XCTAssertThrowsError(try injector.inject(text: "hello", into: targetApp))
    }
}

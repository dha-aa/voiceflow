//
//  FnKeyMonitorTests.swift
//  VoiceFlowTests
//

import XCTest
@testable import voiceflow

@MainActor
final class FnKeyMonitorTests: XCTestCase {
    func test_fnKeyMonitor_callsOnKeyDown_whenFnHeld() async {
        let monitor = FnKeyMonitor(holdThreshold: 0.01)
        let keyDown = expectation(description: "Fn key-down callback")
        var callbackCount = 0
        monitor.onFnKeyDown = {
            callbackCount += 1
            keyDown.fulfill()
        }

        monitor.handleFlagsChangedForTesting(isPressed: true)
        await fulfillment(of: [keyDown], timeout: 1)

        XCTAssertEqual(callbackCount, 1)
        monitor.stop()
    }

    func test_fnKeyMonitor_callsOnKeyUp_whenFnReleased() async {
        let monitor = FnKeyMonitor(holdThreshold: 0.01)
        let keyUp = expectation(description: "Fn key-up callback")
        monitor.onFnKeyDown = {}
        monitor.onFnKeyUp = { keyUp.fulfill() }

        monitor.handleFlagsChangedForTesting(isPressed: true)
        try? await Task.sleep(for: .milliseconds(30))
        monitor.handleFlagsChangedForTesting(isPressed: false)

        await fulfillment(of: [keyUp], timeout: 1)
        monitor.stop()
    }

    func test_fnKeyMonitor_doesNotFire_onSingleTapWithoutHold() async {
        let monitor = FnKeyMonitor(holdThreshold: 0.1)
        var keyDownCount = 0
        var keyUpCount = 0
        monitor.onFnKeyDown = { keyDownCount += 1 }
        monitor.onFnKeyUp = { keyUpCount += 1 }

        monitor.handleFlagsChangedForTesting(isPressed: true)
        monitor.handleFlagsChangedForTesting(isPressed: false)
        try? await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(keyDownCount, 0)
        XCTAssertEqual(keyUpCount, 0)
        monitor.stop()
    }

    func test_fnKeyMonitor_ignoresRepeatedDownEvents() async {
        let monitor = FnKeyMonitor(holdThreshold: 0.01)
        let keyDown = expectation(description: "single Fn key-down callback")
        keyDown.assertForOverFulfill = true
        var keyDownCount = 0
        monitor.onFnKeyDown = {
            keyDownCount += 1
            keyDown.fulfill()
        }

        monitor.handleFlagsChangedForTesting(isPressed: true)
        monitor.handleFlagsChangedForTesting(isPressed: true)
        await fulfillment(of: [keyDown], timeout: 1)
        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(keyDownCount, 1)
        monitor.stop()
    }
}

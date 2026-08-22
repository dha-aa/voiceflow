//
//  AppStateManagerTests.swift
//  VoiceFlowTests
//
//  Created by Dhananjay Singh on 22/08/26.
//

import XCTest
@testable import voiceflow

final class AppStateManagerTests: XCTestCase {
    var stateManager: AppStateManager!
    
    override func setUp() {
        super.setUp()
        stateManager = AppStateManager()
    }
    
    override func tearDown() {
        stateManager = nil
        super.tearDown()
    }
    
    func test_initialState_isIdle() {
        XCTAssertEqual(stateManager.currentState, .idle)
    }
    
    func test_transition_idleToRecording() {
        stateManager.transition(to: .recording)
        XCTAssertEqual(stateManager.currentState, .recording)
    }
    
    func test_transition_recordingToProcessing() {
        stateManager.transition(to: .recording)
        stateManager.transition(to: .processing)
        XCTAssertEqual(stateManager.currentState, .processing)
    }
    
    func test_transition_processingToInjecting() {
        stateManager.transition(to: .recording)
        stateManager.transition(to: .processing)
        stateManager.transition(to: .injecting)
        XCTAssertEqual(stateManager.currentState, .injecting)
    }
    
    func test_transition_injectingToIdle() {
        stateManager.transition(to: .recording)
        stateManager.transition(to: .processing)
        stateManager.transition(to: .injecting)
        stateManager.transition(to: .idle)
        XCTAssertEqual(stateManager.currentState, .idle)
    }
    
    func test_transition_anyStateToError() {
        stateManager.transition(to: .recording)
        stateManager.transition(to: .error(.transcriptionFailed))
        XCTAssertEqual(stateManager.currentState, .error(.transcriptionFailed))
    }
    
    func test_transition_errorToIdle() {
        stateManager.transition(to: .error(.transcriptionFailed))
        stateManager.transition(to: .idle)
        XCTAssertEqual(stateManager.currentState, .idle)
    }
}

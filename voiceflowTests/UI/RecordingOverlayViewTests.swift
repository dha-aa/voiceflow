//
//  RecordingOverlayViewTests.swift
//  VoiceFlowTests
//

import Foundation
import XCTest
@testable import voiceflow

@MainActor
final class RecordingOverlayViewTests: XCTestCase {
    func test_overlayView_showsListeningState_whenRecording() {
        let model = RecordingOverlayModel()

        model.showListeningState()

        XCTAssertEqual(model.presentationState, .listening)
        XCTAssertTrue(model.isVisible)
        XCTAssertFalse(model.isShowingDoneState)
    }

    func test_overlayView_showsProcessingState_whenProcessing() {
        let model = RecordingOverlayModel()

        model.showProcessingState()

        XCTAssertEqual(model.presentationState, .processing)
        XCTAssertTrue(model.isVisible)
        XCTAssertEqual(model.statusText, "Processing...")
    }

    func test_overlayView_identifiesClaudeWhileAIIsProcessing() {
        let model = RecordingOverlayModel()

        model.showAIProcessingState(provider: .claude)

        XCTAssertEqual(model.statusText, "Using Claude...")
        XCTAssertEqual(model.accessibilityStatusText, "Using Claude")
        XCTAssertEqual(model.activeAIProvider, .claude)
    }

    func test_overlayView_identifiesChatGPTForFutureProviderSupport() {
        let model = RecordingOverlayModel()

        model.showAIProcessingState(provider: .chatGPT)

        XCTAssertEqual(model.statusText, "Using ChatGPT...")
        XCTAssertEqual(model.accessibilityStatusText, "Using ChatGPT")
    }

    func test_overlayView_showsProcessingState_whileInjecting() {
        let stateManager = AppStateManager()
        let defaults = UserDefaults(suiteName: "overlay-injecting-\(UUID().uuidString)")!
        let controller = OverlayWindowController(
            stateManager: stateManager,
            userDefaults: defaults
        )

        controller.updateOverlay(for: .injecting)

        XCTAssertEqual(controller.overlayModel.presentationState, .processing)
        XCTAssertTrue(controller.overlayModel.isVisible)
        controller.stop()
    }

    func test_overlayView_showsDoneState_whenCompleted_thenHidesAfter400Milliseconds() async throws {
        let stateManager = AppStateManager()
        let defaults = UserDefaults(suiteName: "overlay-done-\(UUID().uuidString)")!
        let controller = OverlayWindowController(
            stateManager: stateManager,
            userDefaults: defaults
        )

        controller.updateOverlay(for: .completed)
        XCTAssertTrue(controller.overlayModel.isShowingDoneState)
        XCTAssertTrue(controller.overlayModel.isVisible)

        stateManager.transition(to: .idle)
        controller.updateOverlay(for: .idle)
        XCTAssertTrue(controller.overlayModel.isShowingDoneState)

        try await Task.sleep(for: .milliseconds(500))
        XCTAssertFalse(controller.overlayModel.isVisible)
        XCTAssertFalse(controller.overlayModel.isShowingDoneState)
        controller.stop()
    }

    func test_overlayView_cancellationCleansUpDoneState() async throws {
        let stateManager = AppStateManager()
        let defaults = UserDefaults(suiteName: "overlay-cancel-\(UUID().uuidString)")!
        let controller = OverlayWindowController(
            stateManager: stateManager,
            userDefaults: defaults
        )

        controller.updateOverlay(for: .completed)
        XCTAssertTrue(controller.overlayModel.isShowingDoneState)

        controller.updateOverlay(for: .recording)
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(controller.overlayModel.presentationState, .listening)
        XCTAssertFalse(controller.overlayModel.isShowingDoneState)
        controller.stop()
    }

    func test_overlayView_hidden_whenIdle() {
        let stateManager = AppStateManager()
        let defaults = UserDefaults(suiteName: "overlay-idle-\(UUID().uuidString)")!
        let controller = OverlayWindowController(
            stateManager: stateManager,
            userDefaults: defaults
        )

        controller.updateOverlay(for: .idle)

        XCTAssertFalse(controller.overlayModel.isVisible)
        XCTAssertFalse(controller.overlayModel.isShowingDoneState)
        controller.stop()
    }

    func test_overlayView_showsError_withDescription() {
        let model = RecordingOverlayModel()

        model.showErrorState(.transcriptionFailed)

        XCTAssertEqual(model.presentationState, .error(.transcriptionFailed))
        XCTAssertTrue(model.isVisible)
    }

    func test_overlayWindow_isFocusSafe_andAppearsAcrossSpaces() {
        let stateManager = AppStateManager()
        let defaults = UserDefaults(suiteName: "overlay-window-\(UUID().uuidString)")!
        let controller = OverlayWindowController(
            stateManager: stateManager,
            userDefaults: defaults
        )

        XCTAssertTrue(controller.isFocusSafe)
        XCTAssertTrue(controller.appearsAcrossSpaces)
        XCTAssertEqual(controller.overlayFrame.width, 270)
        XCTAssertEqual(controller.overlayFrame.height, 58)
        XCTAssertFalse(controller.hasNativePanelShadow)
        controller.stop()
    }

    func test_overlayView_newStateWinsOverStaleDoneFadeOut() async throws {
        let stateManager = AppStateManager()
        let defaults = UserDefaults(suiteName: "overlay-animation-race-\(UUID().uuidString)")!
        let controller = OverlayWindowController(
            stateManager: stateManager,
            userDefaults: defaults
        )

        controller.updateOverlay(for: .completed)
        try await Task.sleep(for: .milliseconds(410))
        controller.updateOverlay(for: .recording)
        try await Task.sleep(for: .milliseconds(180))

        XCTAssertEqual(controller.overlayModel.presentationState, .listening)
        XCTAssertTrue(controller.overlayModel.isVisible)
        controller.stop()
    }

    func test_overlayView_hidesWhenPreferenceDisabledDuringDoneState() {
        let stateManager = AppStateManager()
        let defaults = UserDefaults(suiteName: "overlay-disable-done-\(UUID().uuidString)")!
        let controller = OverlayWindowController(
            stateManager: stateManager,
            userDefaults: defaults
        )

        controller.updateOverlay(for: .completed)
        XCTAssertTrue(controller.overlayModel.isShowingDoneState)

        defaults.set(false, forKey: "showRecordingOverlay")
        controller.updateOverlay(for: .idle)

        XCTAssertFalse(controller.overlayModel.isVisible)
        XCTAssertFalse(controller.overlayModel.isShowingDoneState)
        controller.stop()
    }

    func test_overlayView_hiddenWhenPreferenceDisabled() {
        let stateManager = AppStateManager()
        let defaults = UserDefaults(suiteName: "overlay-disabled-\(UUID().uuidString)")!
        defaults.set(false, forKey: "showRecordingOverlay")
        let controller = OverlayWindowController(
            stateManager: stateManager,
            userDefaults: defaults
        )

        controller.updateOverlay(for: .recording)

        XCTAssertFalse(controller.overlayModel.isVisible)
        controller.stop()
    }

    func test_overlayModel_clampsAudioLevel() {
        let model = RecordingOverlayModel()

        model.updateAudioLevel(2)
        XCTAssertEqual(model.audioLevel, 1)

        model.updateAudioLevel(-1)
        XCTAssertEqual(model.audioLevel, 0)
    }
}

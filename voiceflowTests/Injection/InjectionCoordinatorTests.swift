//
//  InjectionCoordinatorTests.swift
//  VoiceFlowTests
//

import XCTest
@testable import voiceflow

@MainActor
final class InjectionCoordinatorTests: XCTestCase {
    func test_coordinator_successfulInjection_playsEnabledCompletionSound() async {
        let stateManager = AppStateManager()
        stateManager.transition(to: .injecting)
        let injector = TestTextInjector()
        let soundPlayer = RecordingCompletionSoundPlayer()
        let defaults = UserDefaults(suiteName: "injection-sound-enabled-\(UUID().uuidString)")!
        defaults.set(true, forKey: VoiceFlowSettingsDefaults.playCompletionSoundKey)
        defaults.set(CompletionSoundEffect.pop.rawValue, forKey: VoiceFlowSettingsDefaults.completionSoundEffectKey)
        let coordinator = InjectionCoordinator(
            stateManager: stateManager,
            injector: injector,
            userDefaults: defaults,
            completionSoundPlayer: soundPlayer
        )

        await coordinator.inject(text: "hello", targetApp: nil)

        XCTAssertEqual(stateManager.currentState, .idle)
        XCTAssertEqual(injector.injectedTexts.map(\.text), ["hello"])
        XCTAssertEqual(soundPlayer.playCount, 1)
        XCTAssertEqual(soundPlayer.playedEffects, [.pop])
    }

    func test_coordinator_successfulInjection_doesNotPlayDisabledCompletionSound() async {
        let stateManager = AppStateManager()
        stateManager.transition(to: .injecting)
        let injector = TestTextInjector()
        let soundPlayer = RecordingCompletionSoundPlayer()
        let defaults = UserDefaults(suiteName: "injection-sound-disabled-\(UUID().uuidString)")!
        let coordinator = InjectionCoordinator(
            stateManager: stateManager,
            injector: injector,
            userDefaults: defaults,
            completionSoundPlayer: soundPlayer
        )

        await coordinator.inject(text: "hello", targetApp: nil)

        XCTAssertEqual(stateManager.currentState, .idle)
        XCTAssertEqual(soundPlayer.playCount, 0)
    }

    func test_coordinator_successfulInjection_returnsToIdle() async {
        let stateManager = AppStateManager()
        stateManager.transition(to: .injecting)
        let injector = TestTextInjector()
        let coordinator = InjectionCoordinator(
            stateManager: stateManager,
            injector: injector
        )

        await coordinator.inject(text: "hello", targetApp: nil)

        XCTAssertEqual(stateManager.currentState, .idle)
        XCTAssertEqual(injector.injectedTexts.map(\.text), ["hello"])
    }

    func test_coordinator_injectionFailure_doesNotPlayCompletionSound() async {
        let stateManager = AppStateManager()
        stateManager.transition(to: .injecting)
        let injector = TestTextInjector()
        injector.error = TestInjectionError()
        let soundPlayer = RecordingCompletionSoundPlayer()
        let defaults = UserDefaults(suiteName: "injection-sound-failure-\(UUID().uuidString)")!
        defaults.set(true, forKey: VoiceFlowSettingsDefaults.playCompletionSoundKey)
        let coordinator = InjectionCoordinator(
            stateManager: stateManager,
            injector: injector,
            userDefaults: defaults,
            completionSoundPlayer: soundPlayer
        )

        await coordinator.inject(text: "hello", targetApp: nil)

        XCTAssertEqual(stateManager.currentState, .error(.injectionFailed))
        XCTAssertEqual(soundPlayer.playCount, 0)
    }

    func test_coordinator_injectionFailure_transitionsToError() async {
        let stateManager = AppStateManager()
        stateManager.transition(to: .injecting)
        let injector = TestTextInjector()
        injector.error = TestInjectionError()
        let coordinator = InjectionCoordinator(
            stateManager: stateManager,
            injector: injector
        )

        await coordinator.inject(text: "hello", targetApp: nil)

        XCTAssertEqual(stateManager.currentState, .error(.injectionFailed))
        XCTAssertTrue(injector.injectedTexts.isEmpty)
    }

    func test_coordinator_doesNotInjectOutsideInjectingState() async {
        let stateManager = AppStateManager()
        let injector = TestTextInjector()
        let coordinator = InjectionCoordinator(
            stateManager: stateManager,
            injector: injector
        )

        await coordinator.inject(text: "hello", targetApp: nil)

        XCTAssertEqual(stateManager.currentState, .idle)
        XCTAssertTrue(injector.injectedTexts.isEmpty)
    }
}

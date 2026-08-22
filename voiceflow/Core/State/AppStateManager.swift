//
//  AppStateManager.swift
//  VoiceFlow
//
//  Created by Dhananjay Singh on 22/08/26.
//

import Foundation
import Observation

@Observable
final class AppStateManager {
    private(set) var currentState: AppState = .idle
    private var recoveryTask: Task<Void, Never>?

    func transition(to newState: AppState) {
        // Cancel any pending recovery task when state changes
        recoveryTask?.cancel()
        
        // Log the transition
        print("State transition: \(String(describing: currentState)) -> \(String(describing: newState))")
        
        // Update currentState
        currentState = newState
        
        // Centralized Error Recovery:
        // If state is .error, automatically transition back to .idle after 2 seconds
        if case .error = newState {
            recoveryTask = Task {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self.transition(to: .idle)
            }
        }
    }
}

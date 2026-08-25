//
//  AppState.swift
//  VoiceFlow
//
//  Created by Dhananjay Singh on 22/08/26.
//

import Foundation

enum AppState: Equatable {
    case idle
    case preparingModel
    case recording
    case processing
    case injecting
    case completed
    case copiedToClipboard
    case error(AppError)
}

enum AppError: Error, Equatable {
    case microphoneUnavailable
    case noAudioDetected
    case modelNotInstalled
    case modelFailedToLoad
    case transcriptionFailed
    case claudeNotConfigured
    case claudeRequestFailed
    case injectionFailed
    case accessibilityPermissionDenied
}

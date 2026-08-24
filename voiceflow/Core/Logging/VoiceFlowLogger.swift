//
//  VoiceFlowLogger.swift
//  VoiceFlow
//
//  Shared privacy-safe structured logging for VoiceFlow.
//

import Foundation
import OSLog

enum VoiceFlowLog {
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.voiceflow"

    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let model = Logger(subsystem: subsystem, category: "model")
    static let transcription = Logger(subsystem: subsystem, category: "transcription")
    static let pipeline = Logger(subsystem: subsystem, category: "pipeline")
    static let llm = Logger(subsystem: subsystem, category: "llm")

    nonisolated static func audioIdentifier(for url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }
}

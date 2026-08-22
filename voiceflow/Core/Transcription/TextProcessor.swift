//
//  TextProcessor.swift
//  VoiceFlow
//

import Foundation

struct TextProcessor {
    func process(_ rawText: String) -> String {
        var text = rawText

        // Replace artifacts with a space so adjacent words are not joined.
        let artifacts = [
            "[BLANK_AUDIO]",
            "[blank_audio]",
            "(inaudible)",
            "(INAUDIBLE)"
        ]
        for artifact in artifacts {
            text = text.replacingOccurrences(
                of: artifact,
                with: " ",
                options: [.caseInsensitive]
            )
        }

        return text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

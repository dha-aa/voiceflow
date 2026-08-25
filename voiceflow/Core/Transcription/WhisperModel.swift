//
//  WhisperModel.swift
//  VoiceFlow
//
//  Value types used by the WhisperKit model catalog and Settings UI.
//

import Foundation

struct WhisperModel: Identifiable, Equatable {
    let id: String
    let displayName: String
    let sizeOnDisk: Int64?
    let isDownloaded: Bool
    let isRecommended: Bool
    var isActive: Bool

    init(
        id: String,
        displayName: String? = nil,
        sizeOnDisk: Int64?,
        isDownloaded: Bool,
        isRecommended: Bool,
        isActive: Bool
    ) {
        self.id = id
        self.displayName = displayName ?? Self.makeDisplayName(from: id)
        self.sizeOnDisk = sizeOnDisk
        self.isDownloaded = isDownloaded
        self.isRecommended = isRecommended
        self.isActive = isActive
    }

    private static func makeDisplayName(from id: String) -> String {
        id.replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(whereSeparator: { $0 == " " })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

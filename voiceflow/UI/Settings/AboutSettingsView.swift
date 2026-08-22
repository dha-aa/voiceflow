//
//  AboutSettingsView.swift
//  VoiceFlow
//

import SwiftUI

struct AboutSettingsView: View {
    private let projectURL = URL(string: "https://github.com/dha-aa/voiceflow")!
    private let whisperKitURL = URL(string: "https://github.com/argmaxinc/argmax-oss-swift")!

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 54))
                .foregroundStyle(.tint)

            Text("VoiceFlow")
                .font(.title.bold())

            Text("Fast, private voice input for macOS.")
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                Text("Version \(version) (Build \(build))")
                Text("WhisperKit by Argmax")
            }
            .font(.callout)

            HStack(spacing: 14) {
                Link("VoiceFlow GitHub", destination: projectURL)
                Link("WhisperKit", destination: whisperKitURL)
            }
            .font(.callout)

            Text("MIT License")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .navigationTitle("About")
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }
}

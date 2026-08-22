//
//  WaveformView.swift
//  VoiceFlow
//

import SwiftUI

struct WaveformView: View {
    let audioLevel: Float
    let isDimmed: Bool

    private let variations: [CGFloat] = [
        0.78, 1.00, 0.64, 0.90, 0.72, 1.00,
        0.58, 0.86, 0.68, 0.96, 0.62, 0.84
    ]

    init(audioLevel: Float, isDimmed: Bool = false) {
        self.audioLevel = audioLevel
        self.isDimmed = isDimmed
    }

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(Array(variations.enumerated()), id: \.offset) { _, variation in
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(isDimmed ? 0.34 : 0.86))
                    .frame(width: 3, height: barHeight(for: variation))
            }
        }
        .frame(width: 84, height: 20, alignment: .center)
        .animation(
            .spring(response: 0.15, dampingFraction: 0.6),
            value: clampedAudioLevel
        )
        .accessibilityLabel("Microphone waveform")
        .accessibilityValue(isDimmed ? "Paused" : "Audio level \(Int(clampedAudioLevel * 100)) percent")
    }

    private var clampedAudioLevel: CGFloat {
        CGFloat(min(max(audioLevel, 0), 1))
    }

    private func barHeight(for variation: CGFloat) -> CGFloat {
        let minimum: CGFloat = 3
        let maximum: CGFloat = 18
        let level = clampedAudioLevel
        let height = minimum + ((maximum - minimum) * level * variation)
        return min(max(height, minimum), maximum)
    }
}

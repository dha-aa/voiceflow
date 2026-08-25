import Foundation
import OSLog

enum AudioRetentionPolicy: String, CaseIterable, Identifiable {
    case immediate = "Delete instantly"
    case fiveHours = "Delete after 5 hours"
    case threeDays = "Delete after 3 days"
    case sevenDays = "Delete after 7 days"
    case never = "Never delete"

    var id: String { rawValue }

    var retentionInterval: TimeInterval? {
        switch self {
        case .immediate:
            0
        case .fiveHours:
            5 * 60 * 60
        case .threeDays:
            3 * 24 * 60 * 60
        case .sevenDays:
            7 * 24 * 60 * 60
        case .never:
            nil
        }
    }
}

final class AudioRetentionManager {
    let audioDirectory: URL

    private let userDefaults: UserDefaults
    private let now: () -> Date
    private let fileManager: FileManager
    private let fixedPolicy: AudioRetentionPolicy?
    private var cleanupTimer: Timer?

    init(
        audioDirectory: URL = AudioRecorder.appAudioDirectory,
        userDefaults: UserDefaults = .standard,
        policy: AudioRetentionPolicy? = nil,
        now: @escaping () -> Date = Date.init,
        fileManager: FileManager = .default
    ) {
        self.audioDirectory = audioDirectory.standardizedFileURL
        self.userDefaults = userDefaults
        self.fixedPolicy = policy
        self.now = now
        self.fileManager = fileManager
    }

    deinit {
        cleanupTimer?.invalidate()
    }

    var policy: AudioRetentionPolicy {
        if let fixedPolicy {
            return fixedPolicy
        }
        let rawValue = userDefaults.string(forKey: VoiceFlowSettingsDefaults.audioRetentionPolicyKey) ?? ""
        return AudioRetentionPolicy(rawValue: rawValue) ?? .never
    }

    func setPolicy(_ policy: AudioRetentionPolicy) {
        userDefaults.set(policy.rawValue, forKey: VoiceFlowSettingsDefaults.audioRetentionPolicyKey)
        cleanupExpiredRecordings()
    }

    func startAutomaticCleanup() {
        cleanupExpiredRecordings()
        guard cleanupTimer == nil else { return }
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            self?.cleanupExpiredRecordings()
        }
    }

    func stopAutomaticCleanup() {
        cleanupTimer?.invalidate()
        cleanupTimer = nil
    }

    func cleanupExpiredRecordings() {
        guard let retentionInterval = policy.retentionInterval else { return }
        let cutoff = now().addingTimeInterval(-retentionInterval)
        for url in audioURLs() {
            guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
                  let modificationDate = attributes[.modificationDate] as? Date,
                  modificationDate <= cutoff else {
                continue
            }
            remove(url, reason: "expired")
        }
    }

    func deleteAllAudio() {
        for url in audioURLs() {
            remove(url, reason: "manual_delete_all")
        }
    }

    private func audioURLs() -> [URL] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: audioDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return urls.filter { $0.pathExtension.caseInsensitiveCompare("wav") == .orderedSame }
    }

    private func remove(_ url: URL, reason: String) {
        do {
            try fileManager.removeItem(at: url)
            VoiceFlowLog.audio.info("recording_file_deleted reason=\(reason, privacy: .public)")
        } catch {
            VoiceFlowLog.audio.error("recording_file_delete_failed reason=\(reason, privacy: .public) error=\(String(describing: error), privacy: .public)")
        }
    }
}

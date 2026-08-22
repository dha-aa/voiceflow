//
//  ModelDownloadCoordinator.swift
//  VoiceFlow
//

import Foundation
import Observation

@MainActor
@Observable
final class ModelDownloadCoordinator {
    let modelManager: ModelManager

    private(set) var activeModelID: String?
    private(set) var progress: Double = 0
    private(set) var errorMessage: String?
    private(set) var isCancelling = false

    private var downloadTask: Task<Void, Never>?
    private var operationID = 0

    init(modelManager: ModelManager) {
        self.modelManager = modelManager
    }


    var isDownloading: Bool {
        activeModelID != nil
    }

    func startDownload(id: String) {
        guard activeModelID == nil else { return }

        operationID += 1
        let currentOperation = operationID
        activeModelID = id
        progress = 0
        errorMessage = nil
        isCancelling = false

        downloadTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                try await modelManager.downloadModel(id: id) { [weak self] update in
                    Task { @MainActor [weak self] in
                        guard let self,
                              self.operationID == currentOperation,
                              self.activeModelID == id,
                              !self.isCancelling else { return }
                        self.progress = min(max(update, 0), 1)
                    }
                }
                try Task.checkCancellation()
                try await modelManager.refreshModels()
                finish(operation: currentOperation)
            } catch is CancellationError {
                finish(operation: currentOperation)
            } catch {
                guard operationID == currentOperation else { return }
                errorMessage = Self.userMessage(for: error)
                activeModelID = nil
                isCancelling = false
                downloadTask = nil
            }
        }
    }

    func cancelDownload() {
        guard activeModelID != nil, !isCancelling else { return }
        isCancelling = true
        downloadTask?.cancel()
    }

    func dismissError() {
        errorMessage = nil
    }

    private func finish(operation: Int) {
        guard operationID == operation else { return }
        activeModelID = nil
        isCancelling = false
        progress = 0
        downloadTask = nil
    }

    private static func userMessage(for error: Error) -> String {
        if let modelError = error as? ModelManager.ModelManagerError {
            switch modelError {
            case .invalidModelIdentifier:
                return "The model identifier is invalid."
            case .modelNotDownloaded:
                return "The model is not installed."
            case .invalidModelDirectory:
                return "The downloaded model failed validation."
            case .modelLoadFailed:
                return "The downloaded model could not be loaded by WhisperKit."
            case .cannotDeleteActiveModel:
                return "Select another active model before deleting this model."
            case .deleteVerificationFailed:
                return "The model could not be fully removed."
            }
        }
        return error.localizedDescription
    }
}

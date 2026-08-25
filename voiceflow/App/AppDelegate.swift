//
//  AppDelegate.swift
//  VoiceFlow
//
//  Created by Dhananjay Singh on 22/08/26.
//

import AppKit
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var composition: ApplicationComposition?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.arguments.contains("--model-preflight") {
            runModelPreflight()
            return
        }

        let composition = ApplicationComposition()
        self.composition = composition
        VoiceFlowLog.model.info(
            "application_identity bundle_identifier=\(Bundle.main.bundleIdentifier ?? "<missing>", privacy: .public) application_support_directory=\(composition.modelManager.downloadBase.deletingLastPathComponent().path, privacy: .public) models_root_directory=\(composition.modelManager.downloadBase.path, privacy: .public)"
        )

        composition.start()
        OnboardingWindowController.shared.showIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        composition?.stop()
        composition = nil
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func runModelPreflight() {
        let modelManager = ModelManager()
        if let modelIDIndex = ProcessInfo.processInfo.arguments.firstIndex(of: "--model-id"),
           ProcessInfo.processInfo.arguments.indices.contains(modelIDIndex + 1) {
            let modelID = ProcessInfo.processInfo.arguments[modelIDIndex + 1]
            modelManager.selectModel(id: modelID)
        }
        let output = modelManager.preflightSelectedModel()?.diagnosticDescription
            ?? ["VoiceFlow Model Preflight", "Selected Model: <none>", "", "RESULT: FAIL"].joined(separator: String(UnicodeScalar(10)))
        FileHandle.standardOutput.write(Data(output.utf8))
        NSApplication.shared.terminate(nil)
    }
}

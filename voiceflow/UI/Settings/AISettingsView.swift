//
//  AISettingsView.swift
//  VoiceFlow
//
//  Claude-first AI provider and model configuration.
//

import SwiftUI

struct AISettingsView: View {
    @AppStorage(AISettings.selectedProviderKey) private var selectedProviderRawValue = AIProvider.claude.rawValue
    @AppStorage(AISettings.commandsEnabledKey) private var claudeCommandsEnabled = false
    @AppStorage(AISettings.modelKey(for: .claude)) private var claudeModel = ClaudeSettings.defaultModel

    @State private var claudeAPIKey = ""
    @State private var hasClaudeAPIKey = false
    @State private var availableClaudeModels: [AIModel] = []
    @State private var isRefreshingModels = false
    @State private var statusMessage: String?
    @State private var statusIsError = false

    private var selectedProvider: AIProvider {
        AIProvider(rawValue: selectedProviderRawValue) ?? .claude
    }

    private var modelChoices: [AIModel] {
        var choices = availableClaudeModels
        if !claudeModel.isEmpty && !choices.contains(where: { $0.id == claudeModel }) {
            choices.insert(AIModel(id: claudeModel), at: 0)
        }
        return choices
    }

    var body: some View {
        Form {
            Section("Provider") {
                Picker("Default provider", selection: $selectedProviderRawValue) {
                    ForEach(AIProvider.allCases) { provider in
                        Label(provider.title, systemImage: provider.systemImage)
                            .tag(provider.rawValue)
                            .disabled(!provider.isAvailable)
                    }
                }
                .onChange(of: selectedProviderRawValue) { _, newValue in
                    guard let provider = AIProvider(rawValue: newValue), provider.isAvailable else {
                        selectedProviderRawValue = AIProvider.claude.rawValue
                        statusMessage = "ChatGPT support is planned but not implemented yet."
                        statusIsError = false
                        return
                    }
                    statusMessage = nil
                }

                Text("VoiceFlow currently supports Claude. The provider setting is designed so ChatGPT can be added without changing the voice pipeline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Claude") {
                Toggle("Enable Claude commands", isOn: $claudeCommandsEnabled)
                Text("Start a spoken request with “Claude” to send only the remaining text to Anthropic. Normal dictation remains local.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if selectedProvider == .claude {
                    SecureField("Anthropic API key", text: $claudeAPIKey)
                        .textFieldStyle(.roundedBorder)
                        .disabled(!claudeCommandsEnabled)

                    HStack {
                        Button("Save API key") {
                            saveClaudeAPIKey()
                        }
                        .disabled(claudeAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if hasClaudeAPIKey {
                            Button("Remove key", role: .destructive) {
                                removeClaudeAPIKey()
                            }
                        }
                    }

                    if hasClaudeAPIKey {
                        Label("API key saved in macOS Keychain", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Add an Anthropic API key before enabling Claude commands.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Claude model") {
                if modelChoices.isEmpty {
                    TextField("Claude model ID", text: $claudeModel)
                        .textFieldStyle(.roundedBorder)
                        .disabled(!claudeCommandsEnabled)
                } else {
                    Picker("Model", selection: $claudeModel) {
                        ForEach(modelChoices) { model in
                            Text(model.displayName == model.id ? model.id : "\(model.displayName) (\(model.id))")
                                .tag(model.id)
                        }
                    }
                    .disabled(!claudeCommandsEnabled)
                }

                HStack {
                    Button {
                        Task { await refreshClaudeModels() }
                    } label: {
                        if isRefreshingModels {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Fetch available models", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(!hasClaudeAPIKey || isRefreshingModels)

                    if !availableClaudeModels.isEmpty {
                        Text("Updated from Anthropic")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Model availability is fetched from Anthropic using your saved key. The model ID can still be entered manually if the API list is unavailable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("ChatGPT") {
                Label("Coming soon", systemImage: "clock")
                    .foregroundStyle(.secondary)
                Text("ChatGPT API-key storage and model discovery will be added in a future provider implementation. No OpenAI request is made by this version.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(statusIsError ? .red : .secondary)
            }
        }
        .formStyle(.grouped)
        .padding(24)
        .navigationTitle("AI")
        .task {
            loadClaudeKeyStatus()
            migrateLegacyClaudeModelIfNeeded()
        }
    }

    private func loadClaudeKeyStatus() {
        do {
            hasClaudeAPIKey = try KeychainAPIKeyStore(provider: .claude).read() != nil
        } catch {
            setStatus("Could not read the Claude API key from Keychain.", isError: true)
        }
    }

    private func saveClaudeAPIKey() {
        let trimmedKey = claudeAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return }
        do {
            try KeychainAPIKeyStore(provider: .claude).save(trimmedKey)
            claudeAPIKey = ""
            hasClaudeAPIKey = true
            setStatus("Claude API key saved securely.", isError: false)
        } catch {
            setStatus("Could not save the Claude API key to Keychain.", isError: true)
        }
    }

    private func removeClaudeAPIKey() {
        do {
            try KeychainAPIKeyStore(provider: .claude).remove()
            claudeAPIKey = ""
            hasClaudeAPIKey = false
            availableClaudeModels = []
            setStatus("Claude API key removed.", isError: false)
        } catch {
            setStatus("Could not remove the Claude API key from Keychain.", isError: true)
        }
    }

    private func refreshClaudeModels() async {
        let apiKey: String?
        do {
            apiKey = try KeychainAPIKeyStore(provider: .claude).read()
        } catch {
            setStatus("Could not read the Claude API key from Keychain.", isError: true)
            return
        }
        guard let apiKey,
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            setStatus("Save a Claude API key before fetching models.", isError: true)
            return
        }

        isRefreshingModels = true
        defer { isRefreshingModels = false }
        do {
            let models = try await LiveClaudeModelCatalogClient().fetchModels(apiKey: apiKey)
            availableClaudeModels = models
            if !models.contains(where: { $0.id == claudeModel }),
               let firstModel = models.first {
                claudeModel = firstModel.id
            }
            setStatus("Fetched \(models.count) Claude models.", isError: false)
        } catch {
            setStatus("Could not fetch Claude models. Check the key and network connection.", isError: true)
        }
    }

    private func migrateLegacyClaudeModelIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: AISettings.modelKey(for: .claude)) == nil,
              let legacyModel = defaults.string(forKey: AISettings.legacyClaudeModelKey),
              !legacyModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        claudeModel = legacyModel
    }

    private func setStatus(_ message: String, isError: Bool) {
        statusMessage = message
        statusIsError = isError
    }
}

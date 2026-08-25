import SwiftUI

struct SnippetsSettingsView: View {
    @Bindable var store: SnippetStore

    @State private var name = ""
    @State private var trigger = ""
    @State private var value = ""
    @State private var editingID: UUID?
    @State private var snippetPendingDeletion: Snippet?
    @State private var isDeletionAlertPresented = false

    private var isEditing: Bool { editingID != nil }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !value.isEmpty
    }

    var body: some View {
        Form {
            Section {
                Text("Create local shortcuts for information and phrases you use repeatedly. VoiceFlow expands matching trigger phrases on-device before injection.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Your Snippets") {
                if store.snippets.isEmpty {
                    Text("No snippets yet. Add one below, such as “my email” → “user@example.com”.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.snippets) { snippet in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(snippet.name)
                                    .font(.headline)
                                Text("Say: \(snippet.trigger)")
                                    .font(.subheadline)
                                Text(snippet.value)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 8)
                            Button("Edit") {
                                beginEditing(snippet)
                            }
                            .buttonStyle(.borderless)
                            Button("Delete", role: .destructive) {
                                snippetPendingDeletion = snippet
                                isDeletionAlertPresented = true
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section(isEditing ? "Edit Snippet" : "Add Snippet") {
                TextField("Name, e.g. My Email", text: $name)
                TextField("Trigger phrase, e.g. my email", text: $trigger)
                TextField("Value, e.g. user@example.com", text: $value, axis: .vertical)
                    .lineLimit(1...4)

                HStack {
                    if isEditing {
                        Button("Cancel") {
                            clearForm()
                        }
                    }
                    Spacer()
                    Button(isEditing ? "Save Changes" : "Add Snippet") {
                        saveSnippet()
                    }
                    .disabled(!canSave)
                }
            }

            Section {
                Label("Snippet values stay on this Mac and are expanded locally. They are not sent to Claude, ChatGPT, or any other network service.", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .navigationTitle("Snippets")
        .alert("Delete Snippet?", isPresented: $isDeletionAlertPresented) {
            Button("Delete", role: .destructive) {
                if let snippet = snippetPendingDeletion {
                    store.delete(id: snippet.id)
                    if editingID == snippet.id {
                        clearForm()
                    }
                }
                snippetPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                snippetPendingDeletion = nil
            }
        } message: {
            Text("Remove “\(snippetPendingDeletion?.name ?? "this snippet")” from VoiceFlow?")
        }
    }

    private func beginEditing(_ snippet: Snippet) {
        editingID = snippet.id
        name = snippet.name
        trigger = snippet.trigger
        value = snippet.value
    }

    private func saveSnippet() {
        guard canSave else { return }
        if let editingID {
            store.update(id: editingID, name: name, trigger: trigger, value: value)
        } else {
            store.add(name: name, trigger: trigger, value: value)
        }
        clearForm()
    }

    private func clearForm() {
        editingID = nil
        name = ""
        trigger = ""
        value = ""
    }
}

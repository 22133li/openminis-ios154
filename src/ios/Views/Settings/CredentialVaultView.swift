import SwiftUI
import UIKit

/// Settings → Credential Vault: the user's named secrets, stored in the
/// Keychain, usable by the agent only through per-use approval
/// (`vault_use_secret`). Values are never shown unmasked without a
/// Face ID / passcode check, and never leave the device except through
/// the user's own iCloud Keychain sync.
struct CredentialVaultView: View {
    @StateObject private var store = CredentialVaultStore.shared
    @State private var showingAdd = false
    @State private var revealEntry: VaultEntry?
    @State private var editingEntry: VaultEntry?

    var body: some View {
        List {
            if store.entries.isEmpty {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "key.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No Saved Credentials")
                            .font(.headline)
                        Text("Store API tokens or passwords here. The agent can use them only with your approval each time — values never appear in chat.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            } else {
                Section {
                    ForEach(store.entries) { entry in
                        Button {
                            revealEntry = entry
                        } label: {
                            HStack {
                                Image(systemName: "key.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white)
                                    .frame(width: 26, height: 26)
                                    .background(.blue, in: Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.name)
                                        .foregroundStyle(.primary)
                                    if !entry.note.isEmpty {
                                        Text(entry.note)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text("••••••")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete(perform: deleteEntries)
                } header: {
                    Text("Credentials")
                } footer: {
                    Text("Tap a credential to view it (Face ID / passcode required). When the agent needs one, it asks for your approval each time; approved credentials are injected as $VAULT_NAME into that turn's shell commands only, and the raw value is never written to chat history.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Credential Vault")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                if !store.entries.isEmpty {
                    EditButton()
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            VaultEntryForm(mode: .add) { _, _ in }
        }
        .sheet(item: $editingEntry) { entry in
            VaultEntryForm(mode: .edit(entry)) { _, _ in }
        }
        .sheet(item: $revealEntry) { entry in
            VaultRevealSheet(entry: entry, onEdit: {
                revealEntry = nil
                // Defer so the reveal sheet fully dismisses first.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    editingEntry = entry
                }
            })
        }
    }

    private func deleteEntries(at offsets: IndexSet) {
        for i in offsets {
            CredentialVaultStore.shared.delete(id: store.entries[i].id)
        }
    }
}

// MARK: - Add / edit form

private struct VaultEntryForm: View {
    enum Mode {
        case add
        case edit(VaultEntry)
    }

    let mode: Mode
    /// (didSave, entry) — informational only; the store publishes changes.
    let onDone: (Bool, VaultEntry?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var value: String = ""
    @State private var showValue = false
    @State private var note: String = ""
    @State private var error: String?

    private var isEdit: Bool {
        if case .edit = mode { return true }
        return false
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    ZStack(alignment: .trailing) {
                        Group {
                            if showValue {
                                TextField(isEdit ? "New value (leave empty to keep)" : "Value", text: $value)
                            } else {
                                SecureField(isEdit ? "New value (leave empty to keep)" : "Value", text: $value)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .padding(.trailing, 28)
                        Button {
                            showValue.toggle()
                        } label: {
                            Image(systemName: showValue ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                    }
                    TextField("Note (optional)", text: $note)
                } footer: {
                    if isEdit {
                        Text("Leave the value empty to keep the current one.")
                    } else {
                        Text("The value is stored in the iOS Keychain. It is never shown in full except after Face ID / passcode.")
                    }
                }

                if let error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(isEdit ? "Edit Credential" : "New Credential")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear {
            if case .edit(let entry) = mode {
                name = entry.name
                note = entry.note
            }
        }
    }

    private func save() {
        let store = CredentialVaultStore.shared
        switch mode {
        case .add:
            guard !value.isEmpty else {
                error = "Value is required."
                return
            }
            if store.add(name: name, value: value, note: note) != nil {
                onDone(true, nil)
                dismiss()
            } else {
                error = "Could not save. The name may already exist."
            }
        case .edit(let entry):
            let newValue = value.isEmpty ? nil : value
            if store.update(id: entry.id, name: name, value: newValue, note: note) {
                onDone(true, entry)
                dismiss()
            } else {
                error = "Could not save. The name may already exist."
            }
        }
    }
}

// MARK: - Reveal auth helper

/// Runs the Face ID / passcode prompt on the main actor and loads the
/// value only after success. Kept outside the view so the .onAppear
/// Task stays small.
private enum VaultRevealAuth {
    @MainActor
    static func run(entry: VaultEntry, done: @escaping (Bool, String?) -> Void) async {
        let ok = await BiometricAuth.authenticate(reason: "Reveal credential \(entry.name)")
        done(ok, ok ? CredentialVaultStore.loadValueSync(forId: entry.id) : nil)
    }
}

// MARK: - Face ID-gated reveal

private struct VaultRevealSheet: View {
    let entry: VaultEntry
    let onEdit: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var authed = false
    @State private var authFailed = false
    @State private var showValue = false
    @State private var revealedValue: String?
    @State private var copied = false
    @State private var didAttemptAuth = false

    var body: some View {
        NavigationView {
            Group {
                if authed {
                    VStack(spacing: 18) {
                        Image(systemName: "key.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.blue)
                        Text(entry.name)
                            .font(.headline)
                        HStack {
                            Text(showValue ? (revealedValue ?? "") : String(repeating: "•", count: 10))
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(4)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                showValue.toggle()
                            } label: {
                                Image(systemName: showValue ? "eye.slash" : "eye")
                            }
                        }
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(10)
                        Button {
                            if let v = revealedValue {
                                UIPasteboard.general.string = v
                                copied = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    copied = false
                                }
                            }
                        } label: {
                            Label(copied ? "Copied" : "Copy", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                        .disabled(revealedValue == nil)
                        if !entry.note.isEmpty {
                            Text(entry.note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding()
                } else if authFailed {
                    VStack(spacing: 12) {
                        Image(systemName: "lock.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Authentication failed")
                            .font(.headline)
                        Text("Face ID / passcode is required to view this credential.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Credential")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if authed {
                        Button("Edit") { onEdit() }
                    }
                }
            }
        }
        .onAppear {
            // Proven pattern (AppLockOverlay): explicit @MainActor task so
            // @State mutation type-checks under Swift 6 strict concurrency.
            guard !didAttemptAuth else { return }
            didAttemptAuth = true
            Task { @MainActor in
                await VaultRevealAuth.run(entry: entry) { ok, value in
                    if ok {
                        revealedValue = value
                        authed = true
                    } else {
                        authFailed = true
                    }
                }
            }
        }
        .onDisappear {
            // Don't leave the plaintext value in memory longer than needed.
            revealedValue = nil
        }
    }
}

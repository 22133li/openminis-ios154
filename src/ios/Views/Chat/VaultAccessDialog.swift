import SwiftUI

/// Presents the per-use approval sheet when the agent calls
/// `vault_use_secret`. Mirrors OffloadPermissionDialogModifier: the sheet
/// is driven by `CredentialVaultAccessManager.pendingRequest` and cannot
/// be swipe-dismissed — the user must explicitly Allow or Deny.
struct VaultAccessDialogModifier: ViewModifier {
    @ObservedObject private var manager = CredentialVaultAccessManager.shared

    func body(content: Content) -> some View {
        content
            .sheet(item: $manager.pendingRequest) { request in
                VaultAccessDialogContent(request: request)
                    .interactiveDismissDisabled()
            }
    }
}

private struct VaultAccessDialogContent: View {
    @ObservedObject private var manager = CredentialVaultAccessManager.shared
    let request: VaultAccessRequest

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 14) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.blue)
                        .padding(.top, 20)
                    Text("Agent Requests a Credential")
                        .font(.headline)
                    Text("“\(request.entryName)”")
                        .font(.title3)
                        .bold()
                        .multilineTextAlignment(.center)
                    if !request.toolTitle.isEmpty {
                        Text(request.toolTitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    if !request.purpose.isEmpty {
                        Text(request.purpose)
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 4)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Approved use is limited to this turn's shell commands via $\(request.envVarName).", systemImage: "terminal")
                        Label("The raw value is never written to chat history.", systemImage: "eye.slash")
                        Label("You can revoke access anytime by deleting the credential.", systemImage: "trash")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            HStack(spacing: 12) {
                Button {
                    manager.respond(to: request.id, allowed: false)
                } label: {
                    Text("Deny")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button {
                    manager.respond(to: request.id, allowed: true)
                } label: {
                    Text("Allow Once")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .background(Color(.systemGroupedBackground))
    }
}

extension View {
    func vaultAccessDialog() -> some View {
        modifier(VaultAccessDialogModifier())
    }
}

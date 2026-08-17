import SwiftUI

public struct SettingsSessionSection: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(ThemeManager.self) private var theme

    @State private var showSignOutConfirm = false
    @State private var showDeleteConfirm = false
    @State private var isWorking = false
    @State private var statusMessage: String?

    public init() {}

    public var body: some View {
        if authManager.authState.isAuthenticated {
            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionHeader(title: "Account")

                VStack(alignment: .leading, spacing: 12) {
                    if let email = authManager.currentUser?.email, !email.isEmpty {
                        Text(email)
                            .font(.system(size: 13))
                            .foregroundStyle(theme.colors.secondaryText)
                    }

                    Button {
                        showSignOutConfirm = true
                    } label: {
                        sessionRow(title: "Sign Out", destructive: false)
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking)
                    .accessibilityLabel("Sign out")
                    .accessibilityIdentifier("Settings_SignOut")

                    Button {
                        showDeleteConfirm = true
                    } label: {
                        sessionRow(title: "Delete Account", destructive: true)
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking)
                    .accessibilityLabel("Delete account")
                    .accessibilityIdentifier("Settings_DeleteAccount")

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(theme.colors.secondaryText)
                    }
                }
                .padding(16)
                .background(theme.colors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
            }
            .alert("Sign Out?", isPresented: $showSignOutConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Sign Out", role: .destructive) {
                    Task { await signOut() }
                }
            } message: {
                Text("You will need to sign in again to sync companion progress.")
            }
            .alert("Delete Account?", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete Account", role: .destructive) {
                    Task { await deleteAccount() }
                }
            } message: {
                Text("This permanently deletes your Kirole account, companion snapshot, and data on this iPhone. This cannot be undone.")
            }
        }
    }

    private func sessionRow(title: String, destructive: Bool) -> some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(destructive ? Color.red : theme.colors.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }

    @MainActor
    private func signOut() async {
        isWorking = true
        defer { isWorking = false }
        await authManager.signOut()
        statusMessage = nil
    }

    @MainActor
    private func deleteAccount() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await authManager.deleteAccount()
            statusMessage = nil
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}

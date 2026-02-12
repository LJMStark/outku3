import SwiftUI

// MARK: - Account Section (Avatar + AI Settings)

public struct SettingsAccountSection: View {
    @Environment(ThemeManager.self) private var theme

    public init() {}

    public var body: some View {
        VStack(spacing: 24) {
            avatarSection
            aiSettingsSection
        }
    }

    // MARK: - Avatar

    private var avatarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "Avatar")

            HStack(spacing: 16) {
                VStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 24)
                            .fill(theme.currentTheme.cardGradient)
                            .frame(width: 96, height: 96)

                        Image("tiko_avatar", bundle: .module)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 80, height: 80)
                            .clipShape(Circle())
                    }

                    Text("Avatar")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(theme.colors.secondaryText)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 24)
                            .fill(Color(hex: "F3F4F6"))
                            .frame(width: 96, height: 96)

                        Image(systemName: "arrow.up.doc")
                            .font(.system(size: 40))
                            .foregroundStyle(Color(hex: "9CA3AF"))
                    }

                    Text("Upload")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(theme.colors.secondaryText)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(20)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        }
    }

    // MARK: - AI Settings

    private var aiSettingsSection: some View {
        AISettingsContent()
    }
}

// MARK: - AI Settings Content

private struct AISettingsContent: View {
    @Environment(ThemeManager.self) private var theme
    @State private var apiKey: String = ""
    @State private var isConfigured: Bool = false
    @State private var showAPIKey: Bool = false
    @State private var isValidating: Bool = false
    @State private var validationMessage: String?
    @State private var isValid: Bool?

    private let keychainService = KeychainService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "AI Features")

            VStack(spacing: 16) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(isConfigured ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)

                    Text(isConfigured ? "OpenAI Connected" : "OpenAI Not Configured")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(theme.colors.primaryText)

                    Spacer()

                    if isConfigured {
                        Button {
                            clearAPIKey()
                        } label: {
                            Text("Remove")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("OpenAI API Key")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.colors.secondaryText)

                    HStack(spacing: 12) {
                        if showAPIKey {
                            TextField("sk-...", text: $apiKey)
                                .font(.system(size: 14, design: .monospaced))
                                .textContentType(.password)
                                .autocorrectionDisabled()
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                #endif
                        } else {
                            SecureField("sk-...", text: $apiKey)
                                .font(.system(size: 14, design: .monospaced))
                                .textContentType(.password)
                        }

                        Button {
                            showAPIKey.toggle()
                        } label: {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                .font(.system(size: 14))
                                .foregroundStyle(theme.colors.secondaryText)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(Color(hex: "F9FAFB"))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if let message = validationMessage {
                    HStack(spacing: 6) {
                        Image(systemName: isValid == true ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(isValid == true ? .green : .red)

                        Text(message)
                            .font(.system(size: 12))
                            .foregroundStyle(isValid == true ? .green : .red)
                    }
                }

                Button {
                    saveAPIKey()
                } label: {
                    HStack {
                        if isValidating {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                        } else {
                            Text("Save API Key")
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(apiKey.isEmpty ? Color.gray.opacity(0.3) : theme.colors.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(apiKey.isEmpty || isValidating)

                Text("Your API key is stored securely in the device keychain and used only for generating personalized haikus.")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.colors.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        }
        .onAppear {
            loadAPIKeyStatus()
        }
    }

    private func loadAPIKeyStatus() {
        isConfigured = keychainService.hasOpenAIAPIKey()
        if isConfigured {
            apiKey = String(repeating: "*", count: 20)
        }
    }

    private func saveAPIKey() {
        guard !apiKey.isEmpty, !apiKey.hasPrefix("*") else { return }

        isValidating = true
        validationMessage = nil

        guard apiKey.hasPrefix("sk-") else {
            isValidating = false
            isValid = false
            validationMessage = "Invalid API key format. Should start with 'sk-'"
            return
        }

        do {
            try keychainService.saveOpenAIAPIKey(apiKey)

            Task {
                await OpenAIService.shared.configure(apiKey: apiKey)
            }

            isConfigured = true
            isValid = true
            validationMessage = "API key saved successfully"
            apiKey = String(repeating: "*", count: 20)

            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                validationMessage = nil
            }
        } catch {
            isValid = false
            validationMessage = "Failed to save API key"
            #if DEBUG
            print("[KeychainError] Failed to save OpenAI API key: \(error.localizedDescription)")
            #endif
        }

        isValidating = false
    }

    private func clearAPIKey() {
        keychainService.clearOpenAIAPIKey()
        isConfigured = false
        apiKey = ""
        validationMessage = nil
    }
}

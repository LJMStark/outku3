import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var appeared = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 24) {
                // Device Section
                DeviceSection()
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 20)
                    .animation(.easeOut(duration: 0.4), value: appeared)

                // Theme Section
                ThemeSection()
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 20)
                    .animation(.easeOut(duration: 0.4).delay(0.1), value: appeared)

                // Avatar Section
                AvatarSection()
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 20)
                    .animation(.easeOut(duration: 0.4).delay(0.2), value: appeared)

                // AI Settings Section
                AISettingsSection()
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 20)
                    .animation(.easeOut(duration: 0.4).delay(0.25), value: appeared)

                // Sound Settings Section
                SoundSettingsSection()
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 20)
                    .animation(.easeOut(duration: 0.4).delay(0.3), value: appeared)

                // Integrations Section
                IntegrationsSection()
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 20)
                    .animation(.easeOut(duration: 0.4).delay(0.35), value: appeared)

                // Debug Section
                DebugSection()
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 20)
                    .animation(.easeOut(duration: 0.4).delay(0.4), value: appeared)

                Spacer()
                    .frame(height: 80)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
        }
        .background(theme.colors.background)
        .onAppear { appeared = true }
    }
}

// MARK: - Section Header

private struct SettingsSectionHeader: View {
    let title: String
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(theme.colors.secondaryText)
            .textCase(.uppercase)
            .tracking(0.5)
    }
}

// MARK: - Device Section

private struct DeviceSection: View {
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "Device")

            // Device preview placeholder
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.white)
                .frame(height: 200)
                .overlay {
                    VStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(theme.colors.accentLight)
                            .frame(width: 120, height: 160)
                            .overlay {
                                VStack(spacing: 8) {
                                    Image(systemName: "display")
                                        .font(.system(size: 40))
                                        .foregroundStyle(theme.colors.secondaryText.opacity(0.5))
                                    Text("E-ink Device")
                                        .font(.system(size: 12))
                                        .foregroundStyle(theme.colors.secondaryText.opacity(0.5))
                                }
                            }
                    }
                }
                .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        }
    }
}

// MARK: - Theme Section

private struct ThemeSection: View {
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "Theme")

            VStack(spacing: 12) {
                ForEach(Array(AppTheme.allCases.enumerated()), id: \.element.id) { index, themeOption in
                    ThemeOptionRow(
                        theme: themeOption,
                        isSelected: themeManager.currentTheme == themeOption
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            themeManager.setTheme(themeOption)
                        }
                    }
                }
            }
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        }
    }
}

// MARK: - Theme Option Row

private struct ThemeOptionRow: View {
    let theme: AppTheme
    let isSelected: Bool
    let action: () -> Void

    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        Button(action: action) {
            HStack {
                Text(theme.rawValue)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(hex: "374151"))

                Spacer()

                // Color preview dots
                HStack(spacing: 6) {
                    ForEach(theme.previewColors, id: \.self) { color in
                        Circle()
                            .fill(color)
                            .frame(width: 20, height: 20)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 2)
                            )
                            .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
                    }
                }

                // Toggle
                ToggleSwitch(isOn: isSelected)
            }
            .padding(16)
            .background(Color(hex: "F9FAFB"))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color(hex: "D1D5DB") : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Toggle Switch

private struct ToggleSwitch: View {
    let isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            RoundedRectangle(cornerRadius: 12)
                .fill(isOn ? Color(hex: "4CAF50") : Color(hex: "E0E0E0"))
                .frame(width: 40, height: 24)

            Circle()
                .fill(Color.white)
                .frame(width: 16, height: 16)
                .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
                .padding(4)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isOn)
    }
}

// MARK: - Avatar Section

private struct AvatarSection: View {
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "Avatar")

            HStack(spacing: 16) {
                // Current Avatar
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

                // Upload Option
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
}

// MARK: - AI Settings Section

private struct AISettingsSection: View {
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
                // Status indicator
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

                // API Key input
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

                // Validation message
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

                // Save button
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

                // Info text
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

        // Basic validation
        guard apiKey.hasPrefix("sk-") else {
            isValidating = false
            isValid = false
            validationMessage = "Invalid API key format. Should start with 'sk-'"
            return
        }

        // Save to keychain
        do {
            try keychainService.saveOpenAIAPIKey(apiKey)

            // Configure OpenAI service
            Task {
                await OpenAIService.shared.configure(apiKey: apiKey)
            }

            isConfigured = true
            isValid = true
            validationMessage = "API key saved successfully"
            apiKey = String(repeating: "*", count: 20)

            // Clear message after delay
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                validationMessage = nil
            }
        } catch {
            isValid = false
            validationMessage = "Failed to save API key"
            print("[KeychainError] Failed to save OpenAI API key: \(error.localizedDescription)")
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

// MARK: - Sound Settings Section

private struct SoundSettingsSection: View {
    @Environment(ThemeManager.self) private var theme
    @State private var soundEnabled: Bool = true
    @State private var volume: Double = 0.7

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "Sound & Haptics")

            VStack(spacing: 16) {
                // Sound toggle
                HStack {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(theme.colors.accent)
                        .frame(width: 24)

                    Text("Sound Effects")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(theme.colors.primaryText)

                    Spacer()

                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            soundEnabled.toggle()
                            SoundService.shared.isSoundEnabled = soundEnabled
                        }
                    } label: {
                        ToggleSwitch(isOn: soundEnabled)
                    }
                    .buttonStyle(.plain)
                }

                if soundEnabled {
                    // Volume slider
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Volume")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(theme.colors.secondaryText)

                            Spacer()

                            Text("\(Int(volume * 100))%")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(theme.colors.secondaryText)
                        }

                        Slider(value: $volume, in: 0...1) { _ in
                            SoundService.shared.volume = Float(volume)
                        }
                        .tint(theme.colors.accent)
                    }
                }

                // Test sound button
                Button {
                    SoundService.shared.playWithHaptic(.taskComplete, haptic: .success)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 14))

                        Text("Test Sound")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(theme.colors.accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(theme.colors.accentLight)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        }
        .onAppear {
            soundEnabled = SoundService.shared.isSoundEnabled
            volume = Double(SoundService.shared.volume)
        }
    }
}

// MARK: - Integrations Section

private struct IntegrationsSection: View {
    @Environment(AppState.self) private var appState
    @Environment(AuthManager.self) private var authManager
    @Environment(ThemeManager.self) private var theme

    @State private var searchText = ""
    @State private var showComingSoon = false
    @State private var isConnecting = false

    private var connectedIntegrations: [Integration] {
        appState.integrations.filter { $0.isConnected }
    }

    private var filteredTypes: [IntegrationType] {
        let types = IntegrationType.displayOrder
        if searchText.isEmpty { return types }
        return types.filter { $0.rawValue.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "Integrations")

            VStack(spacing: 16) {
                if connectedIntegrations.isEmpty {
                    emptyStateView
                } else {
                    connectedAppsView
                }

                Text("For best results, it is recommended to only have 1-2 of your most important calendars enabled at once.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.colors.secondaryText)

                Divider()

                connectNewAppSection
            }
            .padding(16)
            .background(theme.colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        }
        .alert("Coming Soon", isPresented: $showComingSoon) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This integration will be available in a future update.")
        }
        .task {
            syncGoogleConnectionStatus()
        }
    }

    /// Sync AuthManager's Google connection status to AppState integrations
    private func syncGoogleConnectionStatus() {
        if authManager.isGoogleConnected {
            if authManager.hasCalendarAccess {
                appState.updateIntegrationStatus(.googleCalendar, isConnected: true)
            }
            if authManager.hasTasksAccess {
                appState.updateIntegrationStatus(.googleTasks, isConnected: true)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "link.circle")
                .font(.system(size: 32))
                .foregroundStyle(theme.colors.secondaryText.opacity(0.5))
            Text("You don't have any apps connected")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.colors.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var connectedAppsView: some View {
        VStack(spacing: 8) {
            ForEach(connectedIntegrations) { integration in
                ConnectedAppRow(integration: integration) {
                    disconnectIntegration(integration.type)
                }
            }
        }
    }

    private var connectNewAppSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect New App")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.colors.primaryText)

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(theme.colors.secondaryText)
                TextField("Search all apps", text: $searchText)
                    .font(.system(size: 14))
            }
            .padding(12)
            .background(Color(hex: "F3F4F6"))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text("Commonly connected apps")
                .font(.system(size: 12))
                .foregroundStyle(theme.colors.secondaryText)
                .padding(.top, 8)

            VStack(spacing: 0) {
                ForEach(filteredTypes, id: \.self) { type in
                    IntegrationAppRow(type: type) {
                        Task { await connectIntegration(type) }
                    }

                    if type != filteredTypes.last {
                        Divider().padding(.leading, 52)
                    }
                }
            }
        }
    }

    private func connectIntegration(_ type: IntegrationType) async {
        guard type.isSupported else {
            showComingSoon = true
            return
        }

        isConnecting = true
        defer { isConnecting = false }

        do {
            switch type {
            case .googleCalendar, .googleTasks:
                try await authManager.signInWithGoogle()
                appState.updateIntegrationStatus(type, isConnected: true)
                if type == .googleCalendar {
                    await appState.loadGoogleCalendarEvents()
                } else {
                    await appState.loadGoogleTasks()
                }

            case .appleCalendar:
                let granted = await appState.requestAppleCalendarAccess()
                appState.updateIntegrationStatus(type, isConnected: granted)
                if granted {
                    await appState.loadAppleCalendarEvents()
                }

            case .appleReminders:
                let granted = await appState.requestAppleRemindersAccess()
                appState.updateIntegrationStatus(type, isConnected: granted)
                if granted {
                    await appState.loadAppleReminders()
                }

            default:
                showComingSoon = true
            }
        } catch {
            print("Failed to connect \(type.rawValue): \(error)")
        }
    }

    private func disconnectIntegration(_ type: IntegrationType) {
        appState.updateIntegrationStatus(type, isConnected: false)

        if type == .googleCalendar || type == .googleTasks {
            let googleConnected = appState.integrations.contains {
                ($0.type == .googleCalendar || $0.type == .googleTasks) && $0.isConnected
            }
            if !googleConnected {
                Task { await authManager.disconnectGoogle() }
            }
        }
    }
}

// MARK: - Integration App Row

private struct IntegrationAppRow: View {
    let type: IntegrationType
    let onTap: () -> Void

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                IntegrationIcon(type: type)
                    .frame(width: 32, height: 32)

                HStack(spacing: 4) {
                    Text(type.rawValue)
                        .font(.system(size: 15))
                        .foregroundStyle(theme.colors.primaryText)

                    if type.isExperimental {
                        Text("[Experimental]")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.colors.secondaryText)
                    }
                }

                Spacer()

                if !type.isSupported {
                    Text("Coming Soon")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.colors.secondaryText)
                }
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Connected App Row

private struct ConnectedAppRow: View {
    let integration: Integration
    let onDisconnect: () -> Void

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        HStack(spacing: 12) {
            IntegrationIcon(type: integration.type)
                .frame(width: 32, height: 32)

            Text(integration.name)
                .font(.system(size: 15))
                .foregroundStyle(theme.colors.primaryText)

            Spacer()

            Button("Disconnect") {
                onDisconnect()
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.red)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Integration Icon

private struct IntegrationIcon: View {
    let type: IntegrationType

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(iconBackground)

            if type == .googleCalendar || type == .googleTasks {
                GoogleIcon(lineWidth: 3, inset: 3)
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: type.iconName)
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
            }
        }
    }

    private var iconBackground: Color {
        switch type {
        case .appleCalendar, .appleReminders:
            return Color.blue
        case .googleCalendar, .googleTasks:
            return Color.white
        case .outlookCalendar, .microsoftToDo:
            return Color(hex: "0078D4")
        case .todoist:
            return Color(hex: "E44332")
        case .tickTick:
            return Color(hex: "4CAF50")
        case .notion:
            return Color.black
        default:
            return Color.gray
        }
    }
}

// MARK: - Debug Section

private struct DebugSection: View {
    @Environment(AppState.self) private var appState
    @Environment(AuthManager.self) private var authManager
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "Debug Info")

            VStack(alignment: .leading, spacing: 12) {
                // Google Connection Status
                VStack(alignment: .leading, spacing: 8) {
                    Text("Google Auth Status")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.colors.primaryText)

                    DebugRow(label: "isGoogleConnected", value: authManager.isGoogleConnected)
                    DebugRow(label: "hasCalendarAccess", value: authManager.hasCalendarAccess)
                    DebugRow(label: "hasTasksAccess", value: authManager.hasTasksAccess)
                }

                Divider()

                // Data Counts
                VStack(alignment: .leading, spacing: 8) {
                    Text("Data Counts")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.colors.primaryText)

                    DebugCountRow(label: "Total Events", count: appState.events.count)
                    DebugCountRow(label: "Google Events", count: appState.events.filter { $0.source == .google }.count)
                    DebugCountRow(label: "Apple Events", count: appState.events.filter { $0.source == .apple }.count)
                    DebugCountRow(label: "Total Tasks", count: appState.tasks.count)
                }

                Divider()

                // Manual Sync Button
                Button {
                    Task {
                        await appState.syncGoogleData()
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Force Sync Google Data")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(theme.colors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(Color(hex: "FFF3CD"))
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color(hex: "FFE69C"), lineWidth: 1)
            )
        }
    }
}

private struct DebugRow: View {
    let label: String
    let value: Bool

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color(hex: "6B7280"))

            Spacer()

            HStack(spacing: 4) {
                Circle()
                    .fill(value ? Color.green : Color.red)
                    .frame(width: 8, height: 8)

                Text(value ? "true" : "false")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(value ? Color.green : Color.red)
            }
        }
    }
}

private struct DebugCountRow: View {
    let label: String
    let count: Int

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color(hex: "6B7280"))

            Spacer()

            Text("\(count)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(hex: "374151"))
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppState.shared)
        .environment(ThemeManager.shared)
        .environment(AuthManager.shared)
}

import SwiftUI

// MARK: - Settings Integration Section

public struct SettingsIntegrationSection: View {
    @Environment(AppState.self) private var appState
    @Environment(AuthManager.self) private var authManager
    @Environment(ThemeManager.self) private var theme

    @State private var searchText = ""
    @State private var showComingSoon = false
    @State private var isConnecting = false

    public init() {}

    private var connectedIntegrations: [Integration] {
        appState.integrations.filter { $0.isConnected }
    }

    private var filteredTypes: [IntegrationType] {
        let supportedTypes = IntegrationType.displayOrder.filter { $0.isSupported }
        if searchText.isEmpty { return supportedTypes }
        return supportedTypes.filter { $0.rawValue.localizedCaseInsensitiveContains(searchText) }
    }

    public var body: some View {
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
            #if DEBUG
            print("Failed to connect \(type.rawValue): \(error)")
            #endif
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

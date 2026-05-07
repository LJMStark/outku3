import SwiftUI

// MARK: - Settings Integration Section

public struct SettingsIntegrationSection: View {
    @Environment(AppState.self) private var appState
    @Environment(AuthManager.self) private var authManager
    @Environment(ThemeManager.self) private var theme

    @State private var searchText = ""
    @State private var showComingSoon = false
    @State private var isConnecting = false
    @State private var isDisconnecting = false
    @State private var disconnectTarget: IntegrationType?

    public init() {}

    private var connectedIntegrations: [Integration] {
        appState.integrations.filter { $0.isConnected }
    }

    private var connectedTypes: Set<IntegrationType> {
        Set(connectedIntegrations.map(\.type))
    }

    private var filteredTypes: [IntegrationType] {
        let connectableTypes = IntegrationType.displayOrder.filter {
            $0.isSupported && !connectedTypes.contains($0)
        }
        if searchText.isEmpty { return connectableTypes }
        return connectableTypes.filter { $0.rawValue.localizedCaseInsensitiveContains(searchText) }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Integrations")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(theme.colors.primaryText)

            VStack(alignment: .leading, spacing: 16) {
                Text("For best results, it is recommended to only have 1-2 of your most important calendars enabled at once.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.colors.secondaryText)
                    .lineSpacing(2)

                if connectedIntegrations.isEmpty {
                    emptyStateView
                } else {
                    connectedAppsView
                }

                Text("Connect New App")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(theme.colors.primaryText)
                    .padding(.top, 8)

                connectNewAppSection
            }
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        }
        .alert("Coming Soon", isPresented: $showComingSoon) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This integration will be available in a future update.")
        }
        .alert("Disconnect Integration", isPresented: Binding(
            get: { disconnectTarget != nil },
            set: { if !$0 { disconnectTarget = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                disconnectTarget = nil
            }
            Button("Disconnect", role: .destructive) {
                if let target = disconnectTarget {
                    Task { await disconnectIntegration(target) }
                    disconnectTarget = nil
                }
            }
        } message: {
            if let target = disconnectTarget {
                Text("Are you sure you want to disconnect \(target.rawValue)?")
            }
        }
        .task {
            syncGoogleConnectionStatus()
        }
    }

    private func syncGoogleConnectionStatus() {
        appState.syncIntegrationStatusFromAuth()
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
                    disconnectTarget = integration.type
                }
                .disabled(isDisconnecting)
                .opacity(isDisconnecting ? 0.6 : 1.0)
            }
        }
    }

    private var connectNewAppSection: some View {
        let types = filteredTypes

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(theme.colors.secondaryText)
                TextField("Search all apps", text: $searchText)
                    .font(.system(size: 14))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color(hex: "374151"), lineWidth: 1)
            )

            Text("Commonly connected apps")
                .font(.system(size: 12))
                .foregroundStyle(theme.colors.secondaryText)
                .padding(.top, 8)

            VStack(spacing: 0) {
                ForEach(Array(types.enumerated()), id: \.element) { index, type in
                    IntegrationAppRow(type: type) {
                        Task { await connectIntegration(type) }
                    }
                    .disabled(isConnecting || isDisconnecting)
                    .opacity(isConnecting || isDisconnecting ? 0.5 : 1.0)

                    if index < types.count - 1 {
                        Divider().padding(.leading, 52)
                    }
                }
            }
        }
    }

    private func connectIntegration(_ type: IntegrationType) async {
        guard !isConnecting else { return }

        guard type.isSupported else {
            showComingSoon = true
            return
        }

        isConnecting = true
        defer { isConnecting = false }

        do {
            switch type {
            case .googleCalendar, .googleTasks:
                try await connectGoogleIntegration(type)

            case .appleCalendar:
                await connectAppleCalendarIntegration()

            case .appleReminders:
                await connectAppleRemindersIntegration()

            case .notion:
                await connectNotionIntegration()

            case .taskade:
                await connectTaskadeIntegration()

            default:
                showComingSoon = true
            }
        } catch {
            #if DEBUG
            print("Failed to connect \(type.rawValue): \(error)")
            #endif
        }
    }

    private func connectGoogleIntegration(_ type: IntegrationType) async throws {
        try await authManager.ensureGoogleAccess(for: type)

        let hasRequiredAccess = hasGoogleAccess(for: type)
        appState.updateIntegrationStatus(type, isConnected: hasRequiredAccess)
        guard hasRequiredAccess else {
            appState.lastError = permissionDeniedMessage(for: type)
            return
        }

        await appState.syncGoogleData()
    }

    private func connectAppleCalendarIntegration() async {
        let granted = await appState.requestAppleCalendarAccess()
        appState.updateIntegrationStatus(.appleCalendar, isConnected: granted)
        if granted {
            await appState.syncAppleCalendarEvents()
        }
    }

    private func connectAppleRemindersIntegration() async {
        let granted = await appState.requestAppleRemindersAccess()
        appState.updateIntegrationStatus(.appleReminders, isConnected: granted)
        if granted {
            await appState.syncAppleReminders()
        }
    }

    private func needsGoogleSignIn(for type: IntegrationType) -> Bool {
        guard authManager.isGoogleConnected else { return true }
        return !hasGoogleAccess(for: type)
    }

    private func hasGoogleAccess(for type: IntegrationType) -> Bool {
        switch type {
        case .googleCalendar:
            return authManager.hasCalendarAccess
        case .googleTasks:
            return authManager.hasTasksAccess
        default:
            return false
        }
    }

    private func permissionDeniedMessage(for type: IntegrationType) -> String {
        switch type {
        case .googleCalendar:
            return "Google Calendar permission was not granted."
        case .googleTasks:
            return "Google Tasks permission was not granted."
        default:
            return "Google permission was not granted."
        }
    }

    private func disconnectIntegration(_ type: IntegrationType) async {
        guard !isDisconnecting else { return }
        isDisconnecting = true
        defer { isDisconnecting = false }

        appState.updateIntegrationStatus(type, isConnected: false)

        switch type {
        case .googleCalendar, .googleTasks:
            if !appState.hasAnyGoogleIntegrationConnected {
                await authManager.disconnectGoogle()
            }
        case .notion:
            authManager.disconnectNotion()
        case .taskade:
            authManager.disconnectTaskade()
        default:
            break
        }
    }

    // MARK: - Notion

    private func connectNotionIntegration() async {
        do {
            try await authManager.signInWithNotion()
            appState.updateIntegrationStatus(.notion, isConnected: true)
            await appState.syncNotionData()
        } catch {
            appState.lastError = "Failed to connect Notion: \(error.localizedDescription)"
        }
    }

    // MARK: - Taskade

    private func connectTaskadeIntegration() async {
        do {
            try await authManager.signInWithTaskade()
            appState.updateIntegrationStatus(.taskade, isConnected: true)
            await appState.syncTaskadeData()
        } catch {
            appState.lastError = "Failed to connect Taskade: \(error.localizedDescription)"
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
        .buttonStyle(.kiroleRow)
    }
}

// MARK: - Connected App Row

private struct ConnectedAppRow: View {
    let integration: Integration
    let onDisconnect: () -> Void

    @Environment(ThemeManager.self) private var theme
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                IntegrationIcon(type: integration.type)
                    .frame(width: 24, height: 24)

                Text(integration.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(theme.colors.primaryText)

                Spacer()

                SettingsToggleSwitch(isOn: integration.isConnected)
            }

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(usernameDisplay)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.colors.secondaryText)

                    // Per-integration sync timestamps aren't tracked yet; show
                    // a placeholder until Integration gains a lastSyncedAt field.
                    Text("last updated —")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.colors.secondaryText)
                }

                Spacer()

                Button("Manage") {
                    onDisconnect()
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(theme.colors.primaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(hex: "F3F4F6"))
                .clipShape(Capsule())
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: "E5E7EB"), lineWidth: 1)
        )
    }

    private var usernameDisplay: String {
        switch integration.type {
        case .googleCalendar, .googleTasks:
            return authManager.currentUser?.email ?? "—"
        default:
            return "—"
        }
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

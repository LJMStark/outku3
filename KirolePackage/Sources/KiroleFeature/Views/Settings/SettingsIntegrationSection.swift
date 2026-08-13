import AuthenticationServices
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
    @State private var appleCalendarSelectionIntent: AppleCalendarSelectionIntent?
    @State private var projectSelectionTarget: ProviderProjectSelectionTarget?
    @State private var showTickTickRegionPicker = false

    public init() {}

    private var connectedIntegrations: [Integration] {
        appState.integrations.filter { $0.isConnected }
    }

    private var connectedTypes: Set<IntegrationType> {
        Set(connectedIntegrations.map(\.type))
    }

    private var filteredTypes: [IntegrationType] {
        let connectableTypes = IntegrationType.displayOrder.filter {
            !connectedTypes.contains($0)
                && !(connectedTypes.contains(.appleCalendar)
                    && $0.connectionMode == .appleCalendarMediated)
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
                    // 首次连接失败时还没有任何已连接集成——错误必须在空状态下也可见，
                    // 否则齿轮红点把用户引来 Settings 却只看到"没有已连接应用"。
                    unattachedSyncErrorsView
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
            .background(theme.colors.cardBackground)
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
                if target == .outlookCalendar || target == .microsoftToDo {
                    Text("Disconnect Microsoft? Outlook Calendar and Microsoft To Do will both be disconnected and their local sync data will be removed.")
                } else {
                    Text("Are you sure you want to disconnect \(target.rawValue)?")
                }
            }
        }
        .sheet(item: $appleCalendarSelectionIntent) { intent in
            AppleCalendarSelectionSheet(intent: intent)
                .injectAppEnvironment()
        }
        .sheet(item: $projectSelectionTarget) { target in
            ProviderProjectSelectionSheet(target: target)
                .injectAppEnvironment()
        }
        .confirmationDialog(
            "Choose TickTick Service",
            isPresented: $showTickTickRegionPicker,
            titleVisibility: .visible
        ) {
            Button("TickTick International") {
                Task { await connectTickTick(region: .international) }
            }
            Button("TickTick China — Coming Soon") {}
                .disabled(true)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("TickTick International is available after secure server setup. The China service remains disabled until its separate OAuth registration is verified.")
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
                VStack(alignment: .leading, spacing: 4) {
                    ConnectedAppRow(
                        integration: integration,
                        lastSyncedAt: lastSyncedDate(for: integration.type)
                    ) {
                        disconnectTarget = integration.type
                    }
                    .disabled(isDisconnecting)
                    .opacity(isDisconnecting ? 0.6 : 1.0)

                    if integration.type == .appleCalendar {
                        Button("Choose system calendars") {
                            appleCalendarSelectionIntent = .editExisting
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.colors.accent)
                        .padding(.horizontal, 4)
                        .accessibilityIdentifier("settings.appleCalendar.choose")
                    }

                    if integration.type == .todoist {
                        manageProjectsButton(title: "Choose Todoist projects", target: .todoist)
                    }

                    if integration.type == .tickTick, let region = authManager.tickTickRegion {
                        manageProjectsButton(
                            title: region == .international
                                ? "Choose TickTick projects"
                                : "Choose TickTick China projects",
                            target: .tickTick(region)
                        )
                    }

                    if let errorMessage = syncErrorMessage(for: integration.type) {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.red)
                            Text(errorMessage)
                                .font(.system(size: 11))
                                .foregroundStyle(.red)
                        }
                        .padding(.horizontal, 4)
                        .accessibilityLabel("\(integration.type.rawValue) sync error: \(errorMessage)")
                        .accessibilityIdentifier("settings.syncError.\(integration.type.rawValue)")
                    } else if let warningMessage = syncWarningMessage(for: integration.type) {
                        // 黄色=部分失败/离线等降级态：知道即可，无需行动；红色只留整轮失败。
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(theme.colors.warning)
                            Text(warningMessage)
                                .font(.system(size: 11))
                                .foregroundStyle(theme.colors.warning)
                                .lineLimit(3)
                        }
                        .padding(.horizontal, 4)
                        .accessibilityLabel("\(integration.type.rawValue) sync warning: \(warningMessage)")
                        .accessibilityIdentifier("settings.syncWarning.\(integration.type.rawValue)")
                    }
                }
            }

            unattachedSyncErrorsView
        }
    }

    /// 不归属于任何已连接集成的剩余错误（如云备份、连接失败但尚未成为已连接集成的 provider）。
    /// 空状态下 coveredKeys 为空集，等价于展示全部 remoteSyncErrors。
    private var unattachedSyncErrorsView: some View {
        let coveredKeys = Set(connectedIntegrations.map { syncErrorKey(for: $0.type) })
        let remainingProviders = appState.remoteSyncErrors.keys.filter { !coveredKeys.contains($0) }.sorted()
        return Group {
            if !remainingProviders.isEmpty {
                let providerList = remainingProviders.joined(separator: ", ")
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                    Text(providerList + " sync failed")
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
                .padding(.horizontal, 4)
                .padding(.top, 4)
                .accessibilityLabel("Sync error: \(providerList) sync failed")
                .accessibilityIdentifier("settings.syncErrorIndicator")
            }
        }
    }

    /// remoteSyncErrors 的 key 是 provider 显示名，与 IntegrationType 不一一对应
    /// （Google Calendar/Tasks 共用 "Google" 一个 key）。
    private func syncErrorKey(for type: IntegrationType) -> String {
        switch type {
        case .googleCalendar, .googleTasks: return "Google"
        case .outlookCalendar, .microsoftToDo: return "Microsoft"
        case .appleCalendar: return "Apple Calendar"
        case .caldav, .icalWebcal: return "Apple Calendar"
        case .appleReminders: return "Apple Reminders"
        case .notion: return "Notion"
        case .taskade: return "Taskade"
        default: return type.rawValue
        }
    }

    private func syncErrorMessage(for type: IntegrationType) -> String? {
        appState.remoteSyncErrors[syncErrorKey(for: type)]
    }

    private func syncWarningMessage(for type: IntegrationType) -> String? {
        appState.remoteSyncWarnings[syncErrorKey(for: type)]
    }

    private func lastSyncedDate(for type: IntegrationType) -> Date? {
        appState.integrationLastSyncedAt[syncErrorKey(for: type)]
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
            .background(theme.colors.cardBackground)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    // 搜索框用 borderStrong 墨线：输入控件需要看得见的静态轮廓。
                    .stroke(theme.colors.borderStrong, lineWidth: 1)
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
                    .disabled(isConnecting || isDisconnecting || !type.isAvailable)
                    .opacity((isConnecting || isDisconnecting || !type.isAvailable) ? 0.5 : 1.0)

                    if index < types.count - 1 {
                        Divider().padding(.leading, 52)
                    }
                }
            }
        }
    }

    private func connectIntegration(_ type: IntegrationType) async {
        guard !isConnecting else { return }

        guard type.isAvailable else {
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

            case .caldav, .icalWebcal:
                await connectAppleMediatedCalendar()

            case .notion:
                await connectNotionIntegration()

            case .taskade:
                await connectTaskadeIntegration()

            case .outlookCalendar, .microsoftToDo:
                try await connectMicrosoftIntegration(type)

            case .todoist:
                try await connectTodoistIntegration()

            case .tickTick:
                showTickTickRegionPicker = true

            }
        } catch GoogleSignInError.canceled {
            // 用户主动关掉 Google 登录窗：不算错误
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // 用户主动关掉系统 OAuth 登录窗：不算连接失败，也不留下红色错误横幅。
        } catch is CancellationError {
            // MSAL and structured-concurrency cancellation both mean the user left sign-in.
        } catch {
            appState.lastError = error.localizedDescription
            appState.remoteSyncErrors[syncErrorKey(for: type)] = error.localizedDescription
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
            // lastError 在 Release 没有任何读取方——必须同时进 remoteSyncErrors 横幅，用户才看得到。
            appState.lastError = permissionDeniedMessage(for: type)
            appState.remoteSyncErrors["Google"] = permissionDeniedMessage(for: type)
            return
        }

        await appState.syncGoogleData()
    }

    private func connectAppleCalendarIntegration() async {
        await AppleSyncEngine.shared.setEventCalendarSelectionMode(.nativeAppleCalendar)
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

    private func connectAppleMediatedCalendar() async {
        let granted = await appState.requestAppleCalendarAccess()
        guard granted else { return }
        appleCalendarSelectionIntent = .connectMediated
    }

    private func connectMicrosoftIntegration(_ type: IntegrationType) async throws {
        try await authManager.ensureMicrosoftAccess(for: type)
        appState.updateIntegrationStatus(type, isConnected: true)
        await appState.syncMicrosoftData()
    }

    private func connectTodoistIntegration() async throws {
        try await authManager.connectTodoist()
        appState.updateIntegrationStatus(.todoist, isConnected: true)
        projectSelectionTarget = .todoist
    }

    private func connectTickTick(region: TickTickRegion) async {
        guard !isConnecting else { return }
        isConnecting = true
        defer { isConnecting = false }
        do {
            _ = try await authManager.connectTickTick(region: region)
            appState.updateIntegrationStatus(.tickTick, isConnected: true)
            projectSelectionTarget = .tickTick(region)
        } catch {
            appState.lastError = error.localizedDescription
            appState.remoteSyncErrors["TickTick"] = error.localizedDescription
        }
    }

    @ViewBuilder
    private func manageProjectsButton(
        title: String,
        target: ProviderProjectSelectionTarget
    ) -> some View {
        Button(title) {
            projectSelectionTarget = target
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(theme.colors.accent)
        .padding(.horizontal, 4)
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

        do {
            switch type {
            case .googleCalendar, .googleTasks:
                let otherGoogleType: IntegrationType = type == .googleCalendar
                    ? .googleTasks
                    : .googleCalendar
                if !appState.isIntegrationConnected(otherGoogleType) {
                    guard await authManager.disconnectGoogle() else {
                        throw KeychainCleanupError.credentialDeletionFailed
                    }
                }
                appState.updateIntegrationStatus(type, isConnected: false)
            case .notion:
                guard authManager.disconnectNotion() else {
                    throw KeychainCleanupError.credentialDeletionFailed
                }
                appState.updateIntegrationStatus(type, isConnected: false)
            case .taskade:
                guard authManager.disconnectTaskade() else {
                    throw KeychainCleanupError.credentialDeletionFailed
                }
                appState.updateIntegrationStatus(type, isConnected: false)
            case .outlookCalendar, .microsoftToDo:
                // Both capabilities share one MSAL account and token cache. Treat them as one
                // privacy boundary so a capability cannot retain stale scopes or queued writes.
                try await authManager.disconnectMicrosoft()
                appState.updateIntegrationStatus(.outlookCalendar, isConnected: false)
                appState.updateIntegrationStatus(.microsoftToDo, isConnected: false)
            case .todoist:
                try await authManager.disconnectTodoist()
                appState.updateIntegrationStatus(type, isConnected: false)
                await appState.saveProjectSelection([], for: .todoist)
            case .tickTick:
                let region = authManager.tickTickRegion
                try await authManager.disconnectTickTick()
                appState.updateIntegrationStatus(type, isConnected: false)
                if let region {
                    await appState.saveProjectSelection([], for: .tickTick(region))
                }
            default:
                appState.updateIntegrationStatus(type, isConnected: false)
            }
        } catch {
            if type == .tickTick, authManager.isTickTickConnected == false {
                appState.updateIntegrationStatus(type, isConnected: false)
            }
            let message = "Could not disconnect \(type.rawValue): \(error.localizedDescription)"
            appState.lastError = message
            appState.remoteSyncErrors[syncErrorKey(for: type)] = message
        }
    }

    // MARK: - Notion

    private func connectNotionIntegration() async {
        do {
            try await authManager.signInWithNotion()
            appState.updateIntegrationStatus(.notion, isConnected: true)
            await appState.syncNotionData()
        } catch {
            guard !isUserCancellation(error) else { return }
            appState.lastError = "Failed to connect Notion: \(error.localizedDescription)"
            appState.remoteSyncErrors["Notion"] = "Failed to connect Notion: \(error.localizedDescription)"
        }
    }

    /// 用户主动关掉 OAuth 登录窗不是错误——弹"连接失败"横幅只会制造噪音。
    private func isUserCancellation(_ error: Error) -> Bool {
        (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
    }

    // MARK: - Taskade

    private func connectTaskadeIntegration() async {
        do {
            try await authManager.signInWithTaskade()
            appState.updateIntegrationStatus(.taskade, isConnected: true)
            await appState.syncTaskadeData()
        } catch {
            guard !isUserCancellation(error) else { return }
            appState.lastError = "Failed to connect Taskade: \(error.localizedDescription)"
            appState.remoteSyncErrors["Taskade"] = "Failed to connect Taskade: \(error.localizedDescription)"
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

                    if !type.isAvailable {
                        Text("[Coming Soon]")
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
        .accessibilityLabel("Connect \(type.rawValue)")
        .accessibilityIdentifier("Integration_Connect_\(type.rawValue)")
    }
}

// MARK: - Connected App Row

private struct ConnectedAppRow: View {
    let integration: Integration
    let lastSyncedAt: Date?
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

                // 断开入口就是开关本身：列表只含已连接项（开关恒为开），点击=请求
                // 断开并弹确认框。旧的 "Manage" 文字按钮已按产品决定移除（2026-07-02）。
                Button {
                    onDisconnect()
                } label: {
                    SettingsToggleSwitch(isOn: integration.isConnected)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Disconnect \(integration.name)")
                .accessibilityIdentifier("Integration_Toggle_\(integration.name)")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(usernameDisplay)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.colors.secondaryText)

                Text(lastSyncedText)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.colors.secondaryText)
            }
        }
        .padding(16)
        .background(theme.colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(theme.colors.border, lineWidth: 1)
        )
    }

    private var lastSyncedText: String {
        guard let lastSyncedAt else { return "Not synced yet" }
        let relativeTime = AppDateFormatters.relativeTimeText(
            for: lastSyncedAt,
            relativeTo: Date(),
            unitsStyle: .abbreviated
        )
        return "Synced \(relativeTime)"
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
                    .accessibilityHidden(true)
            } else {
                Image(systemName: type.iconName)
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityHidden(true)
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

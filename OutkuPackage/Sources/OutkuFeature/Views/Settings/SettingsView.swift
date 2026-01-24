import SwiftUI

// MARK: - Reusable Components

/// 通用卡片背景修饰符
private struct CardBackgroundModifier: ViewModifier {
    @Environment(ThemeManager.self) private var theme

    func body(content: Content) -> some View {
        content
            .padding(AppSpacing.lg)
            .background {
                RoundedRectangle(cornerRadius: AppCornerRadius.medium)
                    .fill(theme.colors.cardBackground)
            }
    }
}

private extension View {
    func cardBackground() -> some View {
        modifier(CardBackgroundModifier())
    }
}

/// 通用 Section 标题
private struct SectionHeader: View {
    let title: String
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        Text(title)
            .font(AppTypography.headline)
            .foregroundStyle(theme.colors.primaryText)
            .padding(.horizontal, AppSpacing.xl)
    }
}

/// 通用设置行（带图标、标题和 Toggle）
private struct SettingsToggleRow: View {
    let icon: String
    let title: String
    @Binding var isOn: Bool
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(theme.colors.accent)
                .frame(width: 24)

            Text(title)
                .font(AppTypography.body)
                .foregroundStyle(theme.colors.primaryText)

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(theme.colors.accent)
        }
        .cardBackground()
    }
}

/// 通用登录按钮
private struct SignInButton: View {
    let icon: String
    let title: String
    let isLoading: Bool
    let action: () -> Void
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 18))

                Text(title)
                    .font(AppTypography.body)

                Spacer()

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .foregroundStyle(theme.colors.primaryText)
            .cardBackground()
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .padding(.horizontal, AppSpacing.xl)
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                // Header - shared across all main pages
                AppHeaderView()

                // Settings content
                VStack(spacing: AppSpacing.xl) {
                    // Account Section (Sign In)
                    AccountSection()

                    // Widget Preview
                    WidgetPreviewSection()

                    // Pet Form Selection
                    PetFormSelectionSection()

                    // Theme Selection
                    ThemeSelectionSection()

                    // Sound Settings
                    SoundSettingsSection()

                    // Hardware Device
                    HardwareDeviceSection()

                    // Integrations
                    IntegrationsSection()

                    // About
                    AboutSection()

                    // Bottom spacing for tab bar
                    Spacer()
                        .frame(height: 120)
                }
                .padding(.top, AppSpacing.xl)
            }
        }
        .background(theme.colors.background)
        .ignoresSafeArea(edges: .top)
    }
}

// MARK: - Widget Preview Section

struct WidgetPreviewSection: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            SectionHeader(title: "Widget Preview")

            VStack(spacing: AppSpacing.lg) {
                PixelPetView(size: .small, animated: false)
                    .frame(height: 80)

                VStack(spacing: AppSpacing.sm) {
                    HStack {
                        Text("Today")
                            .font(AppTypography.subheadline)
                            .foregroundStyle(theme.colors.secondaryText)

                        Spacer()

                        Text("\(appState.statistics.todayCompleted)/\(appState.statistics.todayTotal)")
                            .font(AppTypography.subheadline)
                            .foregroundStyle(theme.colors.primaryText)
                    }

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(theme.colors.timeline)
                                .frame(height: 6)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(theme.colors.taskComplete)
                                .frame(width: geometry.size.width * appState.statistics.todayPercentage, height: 6)
                        }
                    }
                    .frame(height: 6)
                }

                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.colors.streakActive)

                    Text("\(appState.streak.currentStreak) day streak")
                        .font(AppTypography.caption)
                        .foregroundStyle(theme.colors.primaryText)
                }
            }
            .padding(AppSpacing.xl)
            .background {
                RoundedRectangle(cornerRadius: AppCornerRadius.large)
                    .fill(theme.colors.cardBackground)
                    .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
            }
            .padding(.horizontal, AppSpacing.xl)

            Text("Add this widget to your home screen")
                .font(AppTypography.caption)
                .foregroundStyle(theme.colors.secondaryText)
                .padding(.horizontal, AppSpacing.xl)
        }
    }
}

// MARK: - Theme Selection Section

struct PetFormSelectionSection: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            SectionHeader(title: "Pet Form")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.md) {
                    ForEach(PetForm.allCases, id: \.self) { form in
                        PetFormOptionView(
                            form: form,
                            isSelected: appState.pet.currentForm == form,
                            action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    appState.setPetForm(form)
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, AppSpacing.xl)
            }
        }
    }
}

struct PetFormOptionView: View {
    let form: PetForm
    let isSelected: Bool
    let action: () -> Void
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppSpacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppCornerRadius.medium)
                        .fill(theme.colors.cardBackground)
                        .frame(width: 60, height: 60)

                    Image(systemName: form.iconName)
                        .font(.system(size: 24))
                        .foregroundStyle(isSelected ? theme.colors.accent : theme.colors.secondaryText)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: AppCornerRadius.medium)
                        .stroke(isSelected ? theme.colors.accent : .clear, lineWidth: 3)
                }

                Text(form.rawValue)
                    .font(AppTypography.caption)
                    .foregroundStyle(isSelected ? theme.colors.accent : theme.colors.secondaryText)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Theme Selection Section

struct ThemeSelectionSection: View {
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            SectionHeader(title: "Theme")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.md) {
                    ForEach(AppTheme.allCases) { theme in
                        ThemeOptionView(
                            theme: theme,
                            isSelected: themeManager.currentTheme == theme,
                            action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    themeManager.setTheme(theme)
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, AppSpacing.xl)
            }
        }
    }
}

struct ThemeOptionView: View {
    let theme: AppTheme
    let isSelected: Bool
    let action: () -> Void
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppSpacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppCornerRadius.medium)
                        .fill(theme.colors.background)
                        .frame(width: 60, height: 60)

                    RoundedRectangle(cornerRadius: AppCornerRadius.small)
                        .fill(theme.colors.cardBackground)
                        .frame(width: 40, height: 40)

                    Circle()
                        .fill(theme.colors.accent)
                        .frame(width: 16, height: 16)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: AppCornerRadius.medium)
                        .stroke(isSelected ? themeManager.colors.accent : .clear, lineWidth: 3)
                }

                Text(theme.rawValue)
                    .font(AppTypography.caption)
                    .foregroundStyle(isSelected ? themeManager.colors.accent : themeManager.colors.secondaryText)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sound Settings Section

struct SoundSettingsSection: View {
    @Environment(ThemeManager.self) private var theme
    @State private var soundService = SoundService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            SectionHeader(title: "Sound & Haptics")

            VStack(spacing: AppSpacing.sm) {
                SettingsToggleRow(
                    icon: "speaker.wave.2.fill",
                    title: "Sound Effects",
                    isOn: $soundService.isSoundEnabled
                )
                if soundService.isSoundEnabled {
                    volumeControlCard
                }
            }
            .padding(.horizontal, AppSpacing.xl)
        }
    }

    private var volumeControlCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.colors.secondaryText)

                Slider(value: $soundService.volume, in: 0...1)
                    .tint(theme.colors.accent)

                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.colors.secondaryText)
            }

            Button {
                soundService.playWithHaptic(.taskComplete, haptic: .success)
            } label: {
                HStack {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 16))
                    Text("Test Sound")
                        .font(AppTypography.subheadline)
                }
                .foregroundStyle(theme.colors.accent)
            }
            .buttonStyle(.plain)
        }
        .cardBackground()
    }
}

// MARK: - Hardware Device Section

struct HardwareDeviceSection: View {
    @Environment(ThemeManager.self) private var theme
    @State private var bleService = BLEService.shared
    @State private var showDeviceList = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            SectionHeader(title: "E-ink Device")

            VStack(spacing: AppSpacing.sm) {
                connectionStatusCard

                SettingsToggleRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Auto Reconnect",
                    isOn: $bleService.autoReconnect
                )

                if bleService.connectionState.isConnected {
                    syncButton
                }
            }
            .padding(.horizontal, AppSpacing.xl)
        }
        .sheet(isPresented: $showDeviceList) {
            DeviceListSheet(bleService: bleService, isPresented: $showDeviceList)
        }
    }

    private var connectionStatusCard: some View {
        Button {
            if bleService.connectionState == .connected {
                bleService.disconnect()
            } else {
                showDeviceList = true
            }
        } label: {
            HStack(spacing: AppSpacing.md) {
                ZStack {
                    Circle()
                        .fill(connectionColor.opacity(0.15))
                        .frame(width: 40, height: 40)

                    if bleService.connectionState == .scanning {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: connectionIcon)
                            .font(.system(size: 18))
                            .foregroundStyle(connectionColor)
                    }
                }

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(connectionTitle)
                        .font(AppTypography.body)
                        .foregroundStyle(theme.colors.primaryText)

                    Text(connectionSubtitle)
                        .font(AppTypography.caption)
                        .foregroundStyle(theme.colors.secondaryText)
                }

                Spacer()

                if bleService.connectionState.isConnected {
                    Circle()
                        .fill(theme.colors.taskComplete)
                        .frame(width: 10, height: 10)
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(theme.colors.accent)
                }
            }
            .cardBackground()
        }
        .buttonStyle(.plain)
    }

    private var syncButton: some View {
        Button {
            syncToDevice()
        } label: {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 16))

                Text("Sync to Device")
                    .font(AppTypography.body)

                Spacer()

                if let lastSync = bleService.lastSyncTime {
                    Text(lastSync, style: .relative)
                        .font(AppTypography.caption)
                        .foregroundStyle(theme.colors.secondaryText)
                }
            }
            .foregroundStyle(theme.colors.accent)
            .cardBackground()
        }
        .buttonStyle(.plain)
    }

    private var connectionIcon: String {
        switch bleService.connectionState {
        case .connected, .connecting: return "antenna.radiowaves.left.and.right"
        case .scanning: return "magnifyingglass"
        case .disconnected: return "antenna.radiowaves.left.and.right.slash"
        case .error: return "exclamationmark.triangle"
        }
    }

    private var connectionColor: Color {
        switch bleService.connectionState {
        case .connected: return theme.colors.taskComplete
        case .connecting, .scanning: return theme.colors.accent
        case .disconnected: return theme.colors.secondaryText
        case .error: return .red
        }
    }

    private var connectionTitle: String {
        switch bleService.connectionState {
        case .connected:
            return bleService.connectedDevice?.name ?? "Connected"
        case .connecting:
            return "Connecting..."
        case .scanning:
            return "Scanning..."
        case .disconnected:
            return "No Device Connected"
        case .error(let message):
            return "Error: \(message)"
        }
    }

    private var connectionSubtitle: String {
        switch bleService.connectionState {
        case .connected: return "Tap to disconnect"
        case .connecting, .scanning: return "Please wait..."
        case .disconnected, .error: return "Tap to connect"
        }
    }

    private func syncToDevice() {
        Task {
            let appState = AppState.shared
            try? await bleService.syncAllData(
                pet: appState.pet,
                tasks: appState.tasks,
                events: appState.events,
                weather: appState.weather
            )
        }
    }
}

// MARK: - Device List Sheet

struct DeviceListSheet: View {
    let bleService: BLEService
    @Binding var isPresented: Bool
    @Environment(ThemeManager.self) private var theme
    @State private var isScanning = false
    @State private var devices: [BLEDevice] = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: AppSpacing.lg) {
                if isScanning {
                    VStack(spacing: AppSpacing.md) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Scanning for devices...")
                            .font(AppTypography.body)
                            .foregroundStyle(theme.colors.secondaryText)
                    }
                    .frame(maxHeight: .infinity)
                } else if devices.isEmpty {
                    VStack(spacing: AppSpacing.md) {
                        Image(systemName: "antenna.radiowaves.left.and.right.slash")
                            .font(.system(size: 48))
                            .foregroundStyle(theme.colors.secondaryText)

                        Text("No devices found")
                            .font(AppTypography.headline)
                            .foregroundStyle(theme.colors.primaryText)

                        Text("Make sure your E-ink device is powered on and nearby")
                            .font(AppTypography.subheadline)
                            .foregroundStyle(theme.colors.secondaryText)
                            .multilineTextAlignment(.center)

                        Button("Scan Again") {
                            startScanning()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(theme.colors.accent)
                    }
                    .padding(AppSpacing.xl)
                    .frame(maxHeight: .infinity)
                } else {
                    List(devices) { device in
                        Button {
                            connectToDevice(device)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                    Text(device.name)
                                        .font(AppTypography.body)
                                        .foregroundStyle(theme.colors.primaryText)

                                    Text("Signal: \(device.rssi) dBm")
                                        .font(AppTypography.caption)
                                        .foregroundStyle(theme.colors.secondaryText)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14))
                                    .foregroundStyle(theme.colors.secondaryText)
                            }
                        }
                    }
                    .listStyle(.plain)
                }

                if let error = errorMessage {
                    Text(error)
                        .font(AppTypography.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, AppSpacing.xl)
                }
            }
            .background(theme.colors.background)
            .navigationTitle("Connect Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
        .task {
            startScanning()
        }
    }

    private func startScanning() {
        isScanning = true
        errorMessage = nil
        devices = []

        Task {
            do {
                devices = try await bleService.scanForDevices(timeout: 10)
            } catch {
                errorMessage = error.localizedDescription
            }
            isScanning = false
        }
    }

    private func connectToDevice(_ device: BLEDevice) {
        Task {
            do {
                try await bleService.connect(to: device)
                isPresented = false
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Integrations Section

struct IntegrationsSection: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            SectionHeader(title: "Integrations")

            VStack(spacing: AppSpacing.sm) {
                ForEach(appState.integrations) { integration in
                    IntegrationRowView(integration: integration)
                }
            }
            .padding(.horizontal, AppSpacing.xl)
        }
    }
}

struct IntegrationRowView: View {
    let integration: Integration
    @Environment(ThemeManager.self) private var theme
    @Environment(AppState.self) private var appState
    @State private var isConnecting = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        Button {
            handleIntegrationTap()
        } label: {
            HStack(spacing: AppSpacing.md) {
                ZStack {
                    Circle()
                        .fill(theme.colors.accent.opacity(0.15))
                        .frame(width: 40, height: 40)

                    if isConnecting {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: integration.iconName)
                            .font(.system(size: 18))
                            .foregroundStyle(theme.colors.accent)
                    }
                }

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(integration.name)
                        .font(AppTypography.body)
                        .foregroundStyle(theme.colors.primaryText)

                    Text(statusText)
                        .font(AppTypography.caption)
                        .foregroundStyle(statusColor)
                }

                Spacer()

                if integration.isConnected {
                    Circle()
                        .fill(theme.colors.taskComplete)
                        .frame(width: 10, height: 10)
                } else if canConnect {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(theme.colors.accent)
                } else {
                    Circle()
                        .fill(theme.colors.timeline)
                        .frame(width: 10, height: 10)
                }
            }
            .cardBackground()
        }
        .buttonStyle(.plain)
        .disabled(isConnecting || !canConnect)
        .alert("Connection Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private var statusText: String {
        if isConnecting { return "Connecting..." }
        if integration.isConnected { return "Connected" }
        return canConnect ? "Tap to connect" : "Not connected"
    }

    private var statusColor: Color {
        if integration.isConnected { return theme.colors.taskComplete }
        return canConnect ? theme.colors.accent : theme.colors.secondaryText
    }

    private var canConnect: Bool {
        integration.type != .todoist
    }

    private func handleIntegrationTap() {
        guard !integration.isConnected else { return }

        switch integration.type {
        case .googleCalendar, .googleTasks:
            connectGoogle()
        case .appleCalendar:
            connectApple(
                requestAccess: appState.requestAppleCalendarAccess,
                loadData: appState.loadAppleCalendarEvents,
                errorMessage: "Calendar access denied. Please enable in Settings."
            )
        case .appleReminders:
            connectApple(
                requestAccess: appState.requestAppleRemindersAccess,
                loadData: appState.loadAppleReminders,
                errorMessage: "Reminders access denied. Please enable in Settings."
            )
        case .todoist:
            break
        }
    }

    private func connectGoogle() {
        isConnecting = true
        Task {
            do {
                try await AuthManager.shared.signInWithGoogle()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            isConnecting = false
        }
    }

    private func connectApple(
        requestAccess: @escaping () async -> Bool,
        loadData: @escaping () async -> Void,
        errorMessage deniedMessage: String
    ) {
        isConnecting = true
        Task {
            let granted = await requestAccess()
            if granted {
                await loadData()
            } else {
                errorMessage = deniedMessage
                showError = true
            }
            isConnecting = false
        }
    }
}

// MARK: - Account Section

struct AccountSection: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(AuthManager.self) private var authManager
    @State private var isSigningIn = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            SectionHeader(title: "Account")

            if authManager.authState.isAuthenticated, let user = authManager.currentUser {
                signedInView(user: user)
            } else {
                signInOptionsView
            }
        }
    }

    private func signedInView(user: User) -> some View {
        VStack(spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.md) {
                userAvatar(user)

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(user.displayName ?? "User")
                        .font(AppTypography.body)
                        .foregroundStyle(theme.colors.primaryText)

                    if let email = user.email {
                        Text(email)
                            .font(AppTypography.caption)
                            .foregroundStyle(theme.colors.secondaryText)
                    }
                }

                Spacer()

                providerBadge(for: user.authProvider)
            }
            .cardBackground()

            signOutButton
        }
        .padding(.horizontal, AppSpacing.xl)
    }

    @ViewBuilder
    private func userAvatar(_ user: User) -> some View {
        ZStack {
            Circle()
                .fill(theme.colors.accent.opacity(0.15))
                .frame(width: 50, height: 50)

            if let avatarURL = user.avatarURL {
                AsyncImage(url: avatarURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    personIcon
                }
                .frame(width: 50, height: 50)
                .clipShape(Circle())
            } else {
                personIcon
            }
        }
    }

    private var personIcon: some View {
        Image(systemName: "person.fill")
            .font(.system(size: 20))
            .foregroundStyle(theme.colors.accent)
    }

    private func providerBadge(for provider: AuthProvider) -> some View {
        let isApple = provider == .apple
        return HStack(spacing: 4) {
            Image(systemName: isApple ? "apple.logo" : "g.circle.fill")
                .font(.system(size: 12))
            Text(isApple ? "Apple" : "Google")
                .font(AppTypography.caption)
        }
        .foregroundStyle(theme.colors.secondaryText)
    }

    private var signOutButton: some View {
        Button {
            Task { await authManager.signOut() }
        } label: {
            HStack {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 16))
                Text("Sign Out")
                    .font(AppTypography.body)
                Spacer()
            }
            .foregroundStyle(.red)
            .cardBackground()
        }
        .buttonStyle(.plain)
    }

    private var signInOptionsView: some View {
        VStack(spacing: AppSpacing.sm) {
            Text("Sign in to sync your data across devices")
                .font(AppTypography.subheadline)
                .foregroundStyle(theme.colors.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AppSpacing.xl)

            SignInButton(
                icon: "apple.logo",
                title: "Sign in with Apple",
                isLoading: isSigningIn,
                action: signInWithApple
            )

            SignInButton(
                icon: "g.circle.fill",
                title: "Sign in with Google",
                isLoading: isSigningIn,
                action: signInWithGoogle
            )
        }
        .alert("Sign In Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func signInWithApple() {
        performSignIn { try await authManager.signInWithApple() }
    }

    private func signInWithGoogle() {
        performSignIn { try await authManager.signInWithGoogle() }
    }

    private func performSignIn(_ action: @escaping () async throws -> Void) {
        isSigningIn = true
        Task {
            do {
                try await action()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            isSigningIn = false
        }
    }
}

// MARK: - About Section

struct AboutSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            SectionHeader(title: "About")

            VStack(spacing: AppSpacing.sm) {
                AboutRowView(label: "Version", value: "1.0.0")
                AboutRowView(label: "Build", value: "1")
            }
            .padding(.horizontal, AppSpacing.xl)

            VStack(spacing: AppSpacing.sm) {
                LinkRowView(label: "Privacy Policy", icon: "lock.shield")
                LinkRowView(label: "Terms of Service", icon: "doc.text")
                LinkRowView(label: "Send Feedback", icon: "envelope")
            }
            .padding(.horizontal, AppSpacing.xl)
        }
    }
}

struct AboutRowView: View {
    let label: String
    let value: String
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        HStack {
            Text(label)
                .font(AppTypography.body)
                .foregroundStyle(theme.colors.primaryText)

            Spacer()

            Text(value)
                .font(AppTypography.subheadline)
                .foregroundStyle(theme.colors.secondaryText)
        }
        .cardBackground()
    }
}

struct LinkRowView: View {
    let label: String
    let icon: String
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        Button {
            // Handle link tap
        } label: {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(theme.colors.accent)
                    .frame(width: 24)

                Text(label)
                    .font(AppTypography.body)
                    .foregroundStyle(theme.colors.primaryText)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundStyle(theme.colors.secondaryText)
            }
            .cardBackground()
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SettingsView()
        .environment(AppState.shared)
        .environment(ThemeManager.shared)
}

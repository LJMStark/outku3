import SwiftUI

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
            Text("Widget Preview")
                .font(AppTypography.headline)
                .foregroundStyle(theme.colors.primaryText)
                .padding(.horizontal, AppSpacing.xl)

            // Widget preview card
            VStack(spacing: AppSpacing.lg) {
                // Mini pet display
                PixelPetView(size: .small, animated: false)
                    .frame(height: 80)

                // Today's progress
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

                    // Progress bar
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

                // Streak
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

            // Widget hint
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
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Pet Form")
                .font(AppTypography.headline)
                .foregroundStyle(theme.colors.primaryText)
                .padding(.horizontal, AppSpacing.xl)

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

    private var formIcon: String {
        switch form {
        case .cat: return "cat.fill"
        case .dog: return "dog.fill"
        case .bunny: return "hare.fill"
        case .bird: return "bird.fill"
        case .dragon: return "flame.fill"
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppSpacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppCornerRadius.medium)
                        .fill(theme.colors.cardBackground)
                        .frame(width: 60, height: 60)

                    Image(systemName: formIcon)
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
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Theme")
                .font(AppTypography.headline)
                .foregroundStyle(themeManager.colors.primaryText)
                .padding(.horizontal, AppSpacing.xl)

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
                // Color preview
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

                // Theme name
                Text(theme.rawValue)
                    .font(AppTypography.caption)
                    .foregroundStyle(isSelected ? themeManager.colors.accent : themeManager.colors.secondaryText)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Integrations Section

struct IntegrationsSection: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Integrations")
                .font(AppTypography.headline)
                .foregroundStyle(theme.colors.primaryText)
                .padding(.horizontal, AppSpacing.xl)

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
    @State private var isConnecting = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        Button {
            handleIntegrationTap()
        } label: {
            HStack(spacing: AppSpacing.md) {
                // Icon
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

                // Info
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(integration.name)
                        .font(AppTypography.body)
                        .foregroundStyle(theme.colors.primaryText)

                    Text(statusText)
                        .font(AppTypography.caption)
                        .foregroundStyle(statusColor)
                }

                Spacer()

                // Action indicator
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
            .padding(AppSpacing.lg)
            .background {
                RoundedRectangle(cornerRadius: AppCornerRadius.medium)
                    .fill(theme.colors.cardBackground)
            }
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
        if isConnecting {
            return "Connecting..."
        } else if integration.isConnected {
            return "Connected"
        } else if canConnect {
            return "Tap to connect"
        } else {
            return "Not connected"
        }
    }

    private var statusColor: Color {
        if integration.isConnected {
            return theme.colors.taskComplete
        } else if canConnect {
            return theme.colors.accent
        } else {
            return theme.colors.secondaryText
        }
    }

    private var canConnect: Bool {
        switch integration.type {
        case .googleCalendar, .googleTasks:
            return true
        case .appleCalendar, .appleReminders:
            return true
        case .todoist:
            return false // Not implemented yet
        }
    }

    private func handleIntegrationTap() {
        guard !integration.isConnected else { return }

        switch integration.type {
        case .googleCalendar, .googleTasks:
            connectGoogle()
        case .appleCalendar, .appleReminders:
            // Apple integrations are handled via system permissions
            break
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
            Text("Account")
                .font(AppTypography.headline)
                .foregroundStyle(theme.colors.primaryText)
                .padding(.horizontal, AppSpacing.xl)

            if authManager.authState.isAuthenticated, let user = authManager.currentUser {
                // Logged in state
                signedInView(user: user)
            } else {
                // Not logged in state
                signInOptionsView
            }
        }
    }

    private func signedInView(user: User) -> some View {
        VStack(spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.md) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(theme.colors.accent.opacity(0.15))
                        .frame(width: 50, height: 50)

                    if let avatarURL = user.avatarURL {
                        AsyncImage(url: avatarURL) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            Image(systemName: "person.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(theme.colors.accent)
                        }
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
                    } else {
                        Image(systemName: "person.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(theme.colors.accent)
                    }
                }

                // User info
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

                // Provider badge
                HStack(spacing: 4) {
                    Image(systemName: user.authProvider == .apple ? "apple.logo" : "g.circle.fill")
                        .font(.system(size: 12))
                    Text(user.authProvider == .apple ? "Apple" : "Google")
                        .font(AppTypography.caption)
                }
                .foregroundStyle(theme.colors.secondaryText)
            }
            .padding(AppSpacing.lg)
            .background {
                RoundedRectangle(cornerRadius: AppCornerRadius.medium)
                    .fill(theme.colors.cardBackground)
            }

            // Sign out button
            Button {
                Task {
                    await authManager.signOut()
                }
            } label: {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 16))

                    Text("Sign Out")
                        .font(AppTypography.body)

                    Spacer()
                }
                .foregroundStyle(.red)
                .padding(AppSpacing.lg)
                .background {
                    RoundedRectangle(cornerRadius: AppCornerRadius.medium)
                        .fill(theme.colors.cardBackground)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppSpacing.xl)
    }

    private var signInOptionsView: some View {
        VStack(spacing: AppSpacing.sm) {
            // Description
            Text("Sign in to sync your data across devices")
                .font(AppTypography.subheadline)
                .foregroundStyle(theme.colors.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AppSpacing.xl)

            // Apple Sign In
            Button {
                signInWithApple()
            } label: {
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 18))

                    Text("Sign in with Apple")
                        .font(AppTypography.body)

                    Spacer()

                    if isSigningIn {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                .foregroundStyle(theme.colors.primaryText)
                .padding(AppSpacing.lg)
                .background {
                    RoundedRectangle(cornerRadius: AppCornerRadius.medium)
                        .fill(theme.colors.cardBackground)
                }
            }
            .buttonStyle(.plain)
            .disabled(isSigningIn)
            .padding(.horizontal, AppSpacing.xl)

            // Google Sign In
            Button {
                signInWithGoogle()
            } label: {
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: "g.circle.fill")
                        .font(.system(size: 18))

                    Text("Sign in with Google")
                        .font(AppTypography.body)

                    Spacer()

                    if isSigningIn {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                .foregroundStyle(theme.colors.primaryText)
                .padding(AppSpacing.lg)
                .background {
                    RoundedRectangle(cornerRadius: AppCornerRadius.medium)
                        .fill(theme.colors.cardBackground)
                }
            }
            .buttonStyle(.plain)
            .disabled(isSigningIn)
            .padding(.horizontal, AppSpacing.xl)
        }
        .alert("Sign In Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func signInWithApple() {
        isSigningIn = true
        Task {
            do {
                try await authManager.signInWithApple()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            isSigningIn = false
        }
    }

    private func signInWithGoogle() {
        isSigningIn = true
        Task {
            do {
                try await authManager.signInWithGoogle()
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
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("About")
                .font(AppTypography.headline)
                .foregroundStyle(theme.colors.primaryText)
                .padding(.horizontal, AppSpacing.xl)

            VStack(spacing: AppSpacing.sm) {
                AboutRowView(label: "Version", value: "1.0.0")
                AboutRowView(label: "Build", value: "1")
            }
            .padding(.horizontal, AppSpacing.xl)

            // Links
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
        .padding(AppSpacing.lg)
        .background {
            RoundedRectangle(cornerRadius: AppCornerRadius.medium)
                .fill(theme.colors.cardBackground)
        }
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
            .padding(AppSpacing.lg)
            .background {
                RoundedRectangle(cornerRadius: AppCornerRadius.medium)
                    .fill(theme.colors.cardBackground)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SettingsView()
        .environment(AppState.shared)
        .environment(ThemeManager.shared)
}

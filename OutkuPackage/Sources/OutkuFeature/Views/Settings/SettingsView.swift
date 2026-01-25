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

                // Integrations Section
                IntegrationsSection()
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 20)
                    .animation(.easeOut(duration: 0.4).delay(0.3), value: appeared)

                // Connect New App Section
                ConnectNewAppSection()
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

// MARK: - Integrations Section

private struct IntegrationsSection: View {
    @Environment(ThemeManager.self) private var theme
    @State private var appleRemindersEnabled = true
    @State private var googleCalendarEnabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "Integrations")

            VStack(spacing: 0) {
                Text("Integrations adds 1s incremental to any time 1-2 of the lists supported by your account to apps")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.colors.secondaryText)
                    .padding(.bottom, 16)

                // Apple Reminders
                IntegrationRow(
                    icon: "checkmark",
                    iconBackground: LinearGradient(
                        colors: [Color(hex: "60A5FA"), Color(hex: "3B82F6")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    title: "Apple Reminders",
                    description: "didn't change of use\nany action to Apple reminders",
                    isEnabled: $appleRemindersEnabled
                )

                Rectangle()
                    .fill(Color(hex: "F3F4F6"))
                    .frame(height: 1)
                    .padding(.vertical, 16)

                // Google Calendar
                IntegrationRow(
                    icon: "g.circle.fill",
                    iconBackground: LinearGradient(
                        colors: [Color.white, Color.white],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    title: "Google Calendar",
                    description: "No connected\nany action to Apple reminders",
                    isEnabled: $googleCalendarEnabled,
                    isGoogle: true
                )
            }
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        }
    }
}

// MARK: - Integration Row

private struct IntegrationRow: View {
    let icon: String
    let iconBackground: LinearGradient
    let title: String
    let description: String
    @Binding var isEnabled: Bool
    var isGoogle: Bool = false

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(iconBackground)
                    .frame(width: 40, height: 40)
                    .shadow(color: .black.opacity(isGoogle ? 0.1 : 0), radius: 2, y: 1)

                if isGoogle {
                    GoogleIcon()
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(theme.colors.primaryText)

                    Spacer()

                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isEnabled.toggle()
                        }
                    } label: {
                        ToggleSwitch(isOn: isEnabled)
                    }
                    .buttonStyle(.plain)
                }

                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.colors.secondaryText)
                    .lineSpacing(2)

                Button {
                } label: {
                    Text("Manage")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.colors.primaryText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Color(hex: "F3F4F6"))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
    }
}

// MARK: - Google Icon

private struct GoogleIcon: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white)

            GeometryReader { geo in
                Path { path in
                    let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                    let radius = min(geo.size.width, geo.size.height) / 2 - 3

                    path.addArc(
                        center: center,
                        radius: radius,
                        startAngle: .degrees(-45),
                        endAngle: .degrees(270),
                        clockwise: false
                    )
                }
                .stroke(
                    AngularGradient(
                        colors: [
                            Color(hex: "4285F4"),
                            Color(hex: "34A853"),
                            Color(hex: "FBBC05"),
                            Color(hex: "EA4335"),
                            Color(hex: "4285F4")
                        ],
                        center: .center
                    ),
                    lineWidth: 3
                )
            }
        }
    }
}

// MARK: - Connect New App Section

private struct ConnectNewAppSection: View {
    @Environment(ThemeManager.self) private var theme
    @State private var searchText = ""
    @State private var appeared = false

    private let apps = [
        AppInfo(name: "Outlook Calendar", icon: "📅", color: "#0078D4"),
        AppInfo(name: "Apple Calendar", icon: "", color: "#000"),
        AppInfo(name: "Google Tasks", icon: "", color: "#4285F4"),
        AppInfo(name: "Microsoft To Do", icon: "✓", color: "#2564CF"),
        AppInfo(name: "Todoist", icon: "", color: "#E44332"),
        AppInfo(name: "TickTick", icon: "", color: "#4CAF50"),
        AppInfo(name: "Notion (Experimental)", icon: "", color: "#000"),
        AppInfo(name: "CalDAV", icon: "📅", color: "#666"),
        AppInfo(name: "iCal/WebCal", icon: "📅", color: "#666")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "Connect New App")

            VStack(spacing: 16) {
                // Search Box
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16))
                        .foregroundStyle(Color(hex: "9CA3AF"))

                    TextField("Search of apps", text: $searchText)
                        .font(.system(size: 14))
                        .foregroundStyle(theme.colors.primaryText)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(hex: "F9FAFB"))
                .clipShape(RoundedRectangle(cornerRadius: 16))

                Text("Commonly connected apps")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.colors.secondaryText)

                // App List
                VStack(spacing: 8) {
                    ForEach(Array(apps.enumerated()), id: \.element.name) { index, app in
                        AppRow(app: app)
                            .opacity(appeared ? 1 : 0)
                            .offset(x: appeared ? 0 : -20)
                            .animation(
                                .spring(response: 0.5, dampingFraction: 0.8)
                                .delay(0.5 + Double(index) * 0.05),
                                value: appeared
                            )
                    }
                }
            }
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        }
        .onAppear { appeared = true }
    }
}

// MARK: - App Info

private struct AppInfo {
    let name: String
    let icon: String
    let color: String
}

// MARK: - App Row

private struct AppRow: View {
    let app: AppInfo
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        Button {
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hex: app.color))
                        .frame(width: 32, height: 32)

                    if app.icon.isEmpty {
                        Text(String(app.name.prefix(1)))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Text(app.icon)
                            .font(.system(size: 14))
                    }
                }

                Text(app.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.colors.primaryText)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "9CA3AF"))
            }
            .padding(12)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SettingsView()
        .environment(AppState.shared)
        .environment(ThemeManager.shared)
}

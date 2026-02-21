import SwiftUI

// MARK: - Appear Animation Modifier

private struct AppearAnimation: ViewModifier {
    let delay: Double
    let appeared: Bool

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)
            .animation(.easeOut(duration: 0.4).delay(delay), value: appeared)
    }
}

private extension View {
    func appearAnimation(delay: Double = 0, appeared: Bool) -> some View {
        modifier(AppearAnimation(delay: delay, appeared: appeared))
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var appeared = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 24) {
                SettingsBLESection()
                    .appearAnimation(appeared: appeared)

                DeviceModeSection()
                    .appearAnimation(delay: 0.05, appeared: appeared)

                SettingsThemeSection()
                    .appearAnimation(delay: 0.1, appeared: appeared)

                SettingsAccountSection()
                    .appearAnimation(delay: 0.2, appeared: appeared)

                SoundSettingsSection()
                    .appearAnimation(delay: 0.3, appeared: appeared)

                SettingsIntegrationSection()
                    .appearAnimation(delay: 0.35, appeared: appeared)

                DebugSection()
                    .appearAnimation(delay: 0.4, appeared: appeared)

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

// MARK: - Section Header (shared across settings files)

struct SettingsSectionHeader: View {
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

// MARK: - Toggle Switch (shared across settings files)

struct SettingsToggleSwitch: View {
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
                        SettingsToggleSwitch(isOn: soundEnabled)
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

// MARK: - Debug Section

private struct DebugSection: View {
    @Environment(AppState.self) private var appState
    @Environment(AuthManager.self) private var authManager
    @Environment(ThemeManager.self) private var theme
    @State private var showResetConfirm = false

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
                    DebugRow(label: "googleCalendarLinked", value: appState.integrations.first { $0.type == .googleCalendar }?.isConnected == true)
                    DebugRow(label: "googleTasksLinked", value: appState.integrations.first { $0.type == .googleTasks }?.isConnected == true)
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

                VStack(alignment: .leading, spacing: 6) {
                    Text("Sync Diagnostics")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.colors.primaryText)

                    DebugTextRow(label: "lastGoogleSync", value: appState.lastGoogleSyncDebug)
                    DebugTextRow(label: "lastError", value: appState.lastError ?? "nil")
                }

                Divider()

                // Pet Transformation
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pet Transformation")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.colors.primaryText)

                    Picker("Pet Form", selection: Binding(
                        get: { appState.pet.currentForm },
                        set: { appState.pet.currentForm = $0 }
                    )) {
                        ForEach(PetForm.allCases, id: \.self) { form in
                            Text(form.rawValue).tag(form)
                        }
                    }
                    .pickerStyle(.segmented)
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

                Divider()

                // Reset Onboarding
                Button {
                    showResetConfirm = true
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset Onboarding")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.red.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .alert("Reset Onboarding?", isPresented: $showResetConfirm) {
                    Button("Cancel", role: .cancel) {}
                    Button("Reset", role: .destructive) {
                        Task {
                            await appState.resetOnboarding()
                        }
                    }
                } message: {
                    Text("App will return to the onboarding flow on next launch.")
                }
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

private struct DebugTextRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(hex: "6B7280"))
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(hex: "111827"))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    SettingsView()
        .environment(AppState.shared)
        .environment(ThemeManager.shared)
        .environment(AuthManager.shared)
}

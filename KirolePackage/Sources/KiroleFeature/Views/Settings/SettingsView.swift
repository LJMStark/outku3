import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Appear Animation Modifier

private struct AppearAnimation: ViewModifier {
    let delay: Double
    let appeared: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)
            .animation(
                .kiroleAdaptive(.appleEaseOut.delay(delay), reduceMotion: reduceMotion),
                value: appeared
            )
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
    @State private var showCharacterSwitcher = false

    private var viewportWidth: CGFloat? {
        #if canImport(UIKit)
        return UIScreen.main.bounds.width
        #else
        return nil
        #endif
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 24) {
                DeviceModeSection()
                    .appearAnimation(appeared: appeared)

                SettingsThemeSection()
                    .appearAnimation(delay: 0.05, appeared: appeared)

                SettingsAccountSection()
                    .appearAnimation(delay: 0.1, appeared: appeared)

                SettingsIntegrationSection()
                    .appearAnimation(delay: 0.2, appeared: appeared)

                companionSection
                    .appearAnimation(delay: 0.25, appeared: appeared)

                // Other settings moved below
                SettingsBLESection()
                    .appearAnimation(delay: 0.3, appeared: appeared)

                SettingsFocusSection()
                    .appearAnimation(delay: 0.35, appeared: appeared)

                SoundSettingsSection()
                    .appearAnimation(delay: 0.4, appeared: appeared)

                SettingsAboutSection()
                    .appearAnimation(delay: 0.42, appeared: appeared)

                #if DEBUG
                DebugSection()
                    .appearAnimation(delay: 0.45, appeared: appeared)
                #endif

                Spacer()
                    .frame(height: 80)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .frame(width: viewportWidth)
        }
        .background(theme.colors.background)
        .onAppear { appeared = true }
        .sheet(isPresented: $showCharacterSwitcher) {
            CharacterSwitcherSheet()
                .injectAppEnvironment()
                .presentationDetents([.medium])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(24)
        }
    }

    private var companionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "Companion")

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(appState.userProfile.companionCharacter.displayName)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(theme.colors.primaryText)

                    Text(appState.userProfile.companionStyle.description)
                        .font(.system(size: 13))
                        .foregroundStyle(theme.colors.secondaryText)
                }

                Spacer()

                Button {
                    showCharacterSwitcher = true
                } label: {
                    Text("Switch")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.colors.accent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(theme.colors.accentLight)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("切换伴侣角色")
                .accessibilityIdentifier("Settings_SwitchCompanion")
            }
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        }
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
        .animation(.kiroleGentle, value: isOn)
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
                        withAnimation(.kiroleGentle) {
                            soundEnabled.toggle()
                            SoundService.shared.isSoundEnabled = soundEnabled
                        }
                    } label: {
                        SettingsToggleSwitch(isOn: soundEnabled)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(soundEnabled ? "关闭音效" : "开启音效")
                    .accessibilityIdentifier("Settings_SoundToggle")
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
                        .accessibilityLabel("音量")
                        .accessibilityIdentifier("Settings_VolumeSlider")
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
                .accessibilityLabel("测试音效")
                .accessibilityIdentifier("Settings_TestSound")
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

// MARK: - About / Data Sources Section

private struct SettingsAboutSection: View {
    @Environment(ThemeManager.self) private var theme
    private static let appleWeatherLegalURL = URL(string: "https://weatherkit.apple.com/legal-attribution.html")!

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "Data Sources")

            Link(destination: Self.appleWeatherLegalURL) {
                HStack(spacing: 12) {
                    Image(systemName: "cloud.sun.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(theme.colors.accent)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Weather")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(theme.colors.primaryText)
                        Text("Provided by \u{F8FF} Weather")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.colors.secondaryText)
                    }

                    Spacer()

                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.colors.secondaryText)
                }
                .padding(16)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Apple Weather data source")
            .accessibilityHint("Opens Apple Weather legal data sources")
            .accessibilityIdentifier("Settings_WeatherAttribution")
        }
    }
}

// MARK: - Debug Section

private struct DebugSection: View {
    @Environment(AppState.self) private var appState
    @Environment(AuthManager.self) private var authManager
    @Environment(ThemeManager.self) private var theme
    @State private var showResetConfirm = false
    @State private var energyBottles: Int = 0

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
                .accessibilityLabel("强制同步 Google 数据")
                .accessibilityIdentifier("Debug_ForceSyncGoogle")

                Divider()

                forceDisplaySceneBlock

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
                .accessibilityLabel("重置引导流程")
                .accessibilityIdentifier("Debug_ResetOnboarding")
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
        .task {
            energyBottles = await LocalStorage.shared.loadEnergyBottles()
        }
    }

    private var forceDisplaySceneBlock: some View {
        let currentScene = DisplayScene.currentScene(for: energyBottles)

        return VStack(alignment: .leading, spacing: 8) {
            Text("Force Display Scene")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.colors.primaryText)

            Text("Current: \(englishLabel(for: currentScene)) · \(energyBottles) bottles")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color(hex: "6B7280"))

            HStack(spacing: 8) {
                ForEach(DisplayScene.allCases, id: \.self) { scene in
                    Button {
                        Task { await debugForceScene(scene) }
                    } label: {
                        Text(englishLabel(for: scene))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(scene == currentScene ? theme.colors.accent : Color(hex: "9CA3AF"))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("强制切换到 \(englishLabel(for: scene)) 场景")
                    .accessibilityIdentifier("Debug_ForceScene_\(scene.rawValue)")
                }
            }
        }
    }

    private func englishLabel(for scene: DisplayScene) -> String {
        switch scene {
        case .harbor: return "Harbor"
        case .forest: return "Forest"
        case .nightCity: return "Night City"
        }
    }

    @MainActor
    private func debugForceScene(_ scene: DisplayScene) async {
        if BLEService.shared.connectionState.isConnected {
            do {
                try await BLEService.shared.sendDisplayScene(scene)
                appState.lastError = nil
            } catch {
                appState.lastError = "Force scene failed: \(error.localizedDescription)"
            }
        } else {
            appState.lastError = "Force scene: BLE not connected (Simulator only)"
        }

        if !SimulatorBridge.shared.isConnected {
            SimulatorBridge.shared.connect()
        }
        SimulatorBridge.shared.sendPetStatus(
            petName: appState.userProfile.companionCharacter.displayName,
            petMood: appState.pet.mood.rawValue,
            sceneId: scene.rawValue,
            characterId: appState.userProfile.companionCharacter.rawValue
        )
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

import SwiftUI

// MARK: - Device Mode Section

/// 设备模式设置区域
public struct DeviceModeSection: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader

            VStack(spacing: 16) {
                deviceModeSelector
                demoModeToggle
            }
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        }
    }

    private var sectionHeader: some View {
        Text("DEVICE MODE")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(theme.colors.secondaryText)
            .textCase(.uppercase)
            .tracking(0.5)
    }

    private var deviceModeSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Operating Mode")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.colors.primaryText)

            HStack(spacing: 12) {
                ForEach(DeviceMode.allCases, id: \.self) { mode in
                    DeviceModeButton(
                        mode: mode,
                        isSelected: appState.deviceMode == mode
                    ) {
                        withAnimation(Animation.appStandard) {
                            appState.deviceMode = mode
                        }
                    }
                }
            }
        }
    }

    private var demoModeToggle: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Demo Mode")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(theme.colors.primaryText)

                    Text("Use sample data for testing")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.colors.secondaryText)
                }

                Spacer()

                Button {
                    withAnimation(Animation.appStandard) {
                        if appState.isDemoMode {
                            Task {
                                await appState.disableDemoMode()
                            }
                        } else {
                            appState.enableDemoMode()
                        }
                    }
                } label: {
                    DemoToggleSwitch(isOn: appState.isDemoMode)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(Color(hex: "F9FAFB"))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if appState.isDemoMode {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)

                    Text("Demo mode active - showing sample data")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}

// MARK: - Device Mode Button

private struct DeviceModeButton: View {
    let mode: DeviceMode
    let isSelected: Bool
    let action: () -> Void

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: mode.iconName)
                    .font(.system(size: 24))
                    .foregroundStyle(isSelected ? theme.colors.accent : theme.colors.secondaryText)

                Text(mode.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? theme.colors.primaryText : theme.colors.secondaryText)

                Text(mode.description)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 8)
            .background(isSelected ? theme.colors.accentLight : Color(hex: "F9FAFB"))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? theme.colors.accent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Demo Toggle Switch

private struct DemoToggleSwitch: View {
    let isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            RoundedRectangle(cornerRadius: 12)
                .fill(isOn ? Color.orange : Color(hex: "E0E0E0"))
                .frame(width: 40, height: 24)

            Circle()
                .fill(Color.white)
                .frame(width: 16, height: 16)
                .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
                .padding(4)
        }
        .animation(Animation.appStandard, value: isOn)
    }
}

#Preview {
    DeviceModeSection()
        .padding()
        .environment(AppState.shared)
        .environment(ThemeManager.shared)
}

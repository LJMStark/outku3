import SwiftUI

// MARK: - BLE Details Section

public struct SettingsBLESection: View {
    @Environment(ThemeManager.self) private var theme
    @State private var energyBottles: Int = 0
    @State private var bleService = BLEService.shared
    @State private var trustedDeviceCount: Int = 0
    @State private var blockedDeviceCount: Int = 0
    @State private var showClearIdentityConfirmation = false

    public init() {}

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "Hardware Details")

            bleModeCard
            trustedDevicesCard
            currentSceneCard

            #if DEBUG
            simulatorStatusCard
            #endif
        }
        .task {
            energyBottles = await LocalStorage.shared.loadEnergyBottles()
            await refreshIdentityCounts()
        }
        .alert("Clear Trusted Devices?", isPresented: $showClearIdentityConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                Task { await clearTrustedDevices() }
            }
        } message: {
            Text("This removes remembered and blocked BLE devices. Use it when switching hardware boards during integration.")
        }
    }

    private var bleModeCard: some View {
        let mode = BLEService.configuredSecurityMode
        let isSecure = mode == .secure

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: isSecure ? "lock.shield.fill" : "bolt.horizontal.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSecure ? Color.green : Color.orange)

                Text("BLE Link Mode")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.colors.primaryText)

                Spacer()

                Text(mode.displayTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSecure ? Color.green : Color.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background((isSecure ? Color.green : Color.orange).opacity(0.12))
                    .clipShape(Capsule())
            }

            Text(mode.detailText)
                .font(.system(size: 12))
                .foregroundStyle(theme.colors.secondaryText)

            Text(mode.sourceText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(theme.colors.secondaryText.opacity(0.8))
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }

    private var trustedDevicesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.colors.accent)

                Text("Trusted Devices")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.colors.primaryText)

                Spacer()

                Text("\(trustedDeviceCount)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.colors.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(theme.colors.accent.opacity(0.12))
                    .clipShape(Capsule())
            }

            Text(trustedDeviceDescription)
                .font(.system(size: 12))
                .foregroundStyle(theme.colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                showClearIdentityConfirmation = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))

                    Text("Clear Trusted Devices")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.red.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(trustedDeviceCount == 0 && blockedDeviceCount == 0)
            .opacity(trustedDeviceCount == 0 && blockedDeviceCount == 0 ? 0.45 : 1)
            .accessibilityLabel("清除已信任的 BLE 硬件设备")
            .accessibilityIdentifier("Settings_ClearTrustedBLEDevices")
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }

    @MainActor
    private var currentSceneCard: some View {
        let sceneService = SceneUnlockService.shared
        let currentScene = sceneService.currentSceneId(energyBottles: energyBottles)
        let availableScenes = sceneService.fetchAvailableScenes(energyBottles: energyBottles)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "photo.artframe")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.colors.accent)

                Text("Display Scene")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.colors.primaryText)

                Spacer()

                Text(currentScene)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.colors.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(theme.colors.accent.opacity(0.12))
                    .clipShape(Capsule())
            }

            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.orange)

                Text("\(energyBottles) energy bottles")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.colors.secondaryText)

                Text(" | ")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.colors.secondaryText.opacity(0.4))

                Text("\(availableScenes.count)/\(DisplayScene.allCases.count) scenes unlocked")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.colors.secondaryText)
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }

    private var trustedDeviceDescription: String {
        if trustedDeviceCount == 0 && blockedDeviceCount == 0 {
            return "No BLE device identities are stored."
        }

        let trustedText = trustedDeviceCount == 1
            ? "1 trusted device"
            : "\(trustedDeviceCount) trusted devices"
        let blockedText = blockedDeviceCount == 1
            ? "1 blocked device"
            : "\(blockedDeviceCount) blocked devices"

        return "\(trustedText), \(blockedText). Clear this before switching ESP32-S3 boards in secure mode."
    }

    private func refreshIdentityCounts() async {
        trustedDeviceCount = await BLEDeviceIdentityStore.shared.trustedDeviceCount()
        blockedDeviceCount = await BLEDeviceIdentityStore.shared.blockedDeviceCount()
    }

    private func clearTrustedDevices() async {
        await bleService.clearTrustedDevices()
        await refreshIdentityCounts()
    }

    #if DEBUG
    @MainActor
    private var simulatorStatusCard: some View {
        let isConnected = SimulatorBridge.shared.isConnected

        return HStack(spacing: 10) {
            Circle()
                .fill(isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            Text("E-ink Simulator")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.colors.primaryText)

            Spacer()

            Text(isConnected ? "Connected" : "Disconnected")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isConnected ? Color.green : theme.colors.secondaryText)
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }
    #endif
}

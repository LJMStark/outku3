import SwiftUI

// MARK: - BLE Details Section

public struct SettingsBLESection: View {
    @Environment(ThemeManager.self) private var theme
    @State private var energyBottles: Int = 0
    @State private var bleService = BLEService.shared
    @State private var trustedDeviceCount: Int = 0
    @State private var blockedDeviceCount: Int = 0
    @State private var showForgetDeviceConfirmation = false
    @State private var screenSize: ScreenSize = .fourInch

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "Hardware Details")

            syncStatusCard
            pairedDeviceCard
            currentSceneCard
            screenSizeCard

            #if DEBUG
            simulatorStatusCard
            #endif
        }
        .task {
            energyBottles = await LocalStorage.shared.loadEnergyBottles()
            screenSize = bleService.hardwareScreenSize
            await refreshIdentityCounts()
        }
        .onChange(of: bleService.connectionState) { _, _ in
            Task { await refreshIdentityCounts() }
        }
        .alert("Forget Kirole Device?", isPresented: $showForgetDeviceConfirmation) {
            Button("Cancel", role: .cancel) {}
                .accessibilityLabel("Cancel forgetting Kirole device")
                .accessibilityIdentifier("Settings_CancelForgetKiroleDevice")
            Button("Forget", role: .destructive) {
                Task { await forgetKiroleDevice() }
            }
            .accessibilityLabel("Forget Kirole device")
            .accessibilityIdentifier("Settings_ConfirmForgetKiroleDevice")
        } message: {
            Text("This disconnects the current device and removes its pairing record. You can pair a Kirole device again afterward.")
        }
    }

    private var pairedDeviceCard: some View {
        let hasStoredIdentity = bleService.connectionState.isConnected || trustedDeviceCount > 0
            || blockedDeviceCount > 0

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.colors.accent)
                    .accessibilityHidden(true)

                Text("Paired Device")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.colors.primaryText)

                Spacer()
            }

            Text(
                hasStoredIdentity
                ? "Forget this device before pairing a replacement Kirole."
                : "No Kirole device is remembered."
            )
            .font(.system(size: 12))
            .foregroundStyle(theme.colors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)

            Button {
                showForgetDeviceConfirmation = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14, weight: .bold))

                    Text("Forget Kirole Device")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.red.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(!hasStoredIdentity)
            .opacity(hasStoredIdentity ? 1 : 0.45)
            .accessibilityLabel("Forget Kirole device")
            .accessibilityHint(
                hasStoredIdentity
                ? "Disconnects this device and allows a replacement Kirole to be paired."
                : "No Kirole device is remembered."
            )
            .accessibilityIdentifier("Settings_ForgetKiroleDevice")
        }
        .padding(16)
        .background(theme.colors.cardBackground)
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
        .background(theme.colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }

    @MainActor
    private var screenSizeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.ratio.3.to.4")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.orange)
                    .accessibilityHidden(true)

                Text("E-ink Screen Size")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.colors.primaryText)

                Spacer()
            }

            Picker("E-ink screen size", selection: $screenSize) {
                Text(ScreenSize.fourInch.displayName)
                    .accessibilityLabel("4 inches")
                    .tag(ScreenSize.fourInch)
                Text(ScreenSize.sevenInch.displayName)
                    .accessibilityLabel("7.3 inches")
                    .tag(ScreenSize.sevenInch)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("E-ink screen size")
            .accessibilityHint("Match the screen size of your Kirole device.")
            .accessibilityIdentifier("Settings_BLEScreenSizePicker")

            Text("Match your Kirole device. The 7.3\" panel shows up to 5 top tasks; the 4\" panel shows 3.")
                .font(.system(size: 12))
                .foregroundStyle(theme.colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(theme.colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        .onChange(of: screenSize) { _, newValue in
            guard newValue != bleService.hardwareScreenSize else { return }
            bleService.hardwareScreenSize = newValue
            Task { await BLESyncCoordinator.shared.performSync(force: true) }
        }
    }

    // 失败状态必须用户可见：lastSyncTime 只在成功时更新，连续失败时硬件显示旧数据，
    // 用户只看到一个越来越旧的时间戳——没有这张卡，"同步失败"与"还没到同步窗口"不可区分。
    @MainActor
    private var syncStatusCard: some View {
        let failed = bleService.lastSyncFailed
        let lastSyncText: String
        if let lastSync = bleService.lastSyncTime {
            lastSyncText = AppDateFormatters.relativeTimeText(
                for: lastSync,
                relativeTo: Date()
            )
        } else {
            lastSyncText = "Not yet synced"
        }

        return HStack(spacing: 10) {
            Circle()
                .fill(failed ? Color.red : Color.green)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(failed ? "Last sync failed" : "Last Sync")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(failed ? Color.red : theme.colors.primaryText)
                Text(failed ? "Tap to retry now" : lastSyncText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.colors.secondaryText)
            }

            Spacer()

            if failed {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.colors.secondaryText)
            }
        }
        .padding(16)
        .background(theme.colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .onTapGesture {
            guard failed else { return }
            Task { await BLESyncCoordinator.shared.performSync(force: true) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(failed ? "Last sync failed. Tap to retry." : "Last sync \(lastSyncText)")
        .accessibilityIdentifier("settings.ble.syncStatus")
    }

    private func refreshIdentityCounts() async {
        trustedDeviceCount = await BLEDeviceIdentityStore.shared.trustedDeviceCount()
        blockedDeviceCount = await BLEDeviceIdentityStore.shared.blockedDeviceCount()
    }

    private func forgetKiroleDevice() async {
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
        .background(theme.colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }
    #endif
}

import SwiftUI

// MARK: - BLE Details Section

public struct SettingsBLESection: View {
    @Environment(ThemeManager.self) private var theme
    @State private var energyBottles: Int = 0
    @State private var bleService = BLEService.shared
    @State private var trustedDeviceCount: Int = 0
    @State private var blockedDeviceCount: Int = 0
    @State private var showClearIdentityConfirmation = false
    @State private var keepAliveEnabled = false
    @State private var screenSize: ScreenSize = .fourInch

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
            syncStatusCard
            trustedDevicesCard
            currentSceneCard
            screenSizeCard

            // 固件联调开关：DEBUG 包恒显示；Release 包仅 TestFlight 显示；正式上架包隐藏。
            if AppBuildEnvironment.showsHardwareDebugTools {
                keepAliveCard
            }

            #if DEBUG
            simulatorStatusCard
            #endif
        }
        .task {
            energyBottles = await LocalStorage.shared.loadEnergyBottles()
            keepAliveEnabled = bleService.keepAliveDebugMode
            screenSize = bleService.hardwareScreenSize
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
            .accessibilityLabel("Clear trusted BLE devices")
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

    @MainActor
    private var screenSizeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.ratio.3.to.4")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.orange)

                Text("E-ink Screen Size")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.colors.primaryText)

                Spacer()
            }

            Picker("E-ink screen size", selection: $screenSize) {
                Text(ScreenSize.fourInch.displayName).tag(ScreenSize.fourInch)
                Text(ScreenSize.sevenInch.displayName).tag(ScreenSize.sevenInch)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("E-ink screen size")
            .accessibilityIdentifier("Settings_BLEScreenSizePicker")

            Text("Match your Kirole device. The 7.3\" panel shows up to 5 top tasks; the 4\" panel shows 3.")
                .font(.system(size: 12))
                .foregroundStyle(theme.colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        .onChange(of: screenSize) { _, newValue in
            guard newValue != bleService.hardwareScreenSize else { return }
            bleService.hardwareScreenSize = newValue
            // 上限变化改变 DayPack 内容（TopTasks 条数），立即推一轮让硬件对齐。
            Task { await BLESyncCoordinator.shared.performSync(force: true) }
        }
    }

    @MainActor
    private var keepAliveCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(keepAliveEnabled ? Color.orange : theme.colors.secondaryText)

                Text("Keep BLE Connected")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.colors.primaryText)

                Spacer()

                Toggle("", isOn: $keepAliveEnabled)
                    .labelsHidden()
                    .tint(Color.orange)
                    .accessibilityLabel("Keep BLE connected for firmware debugging")
                    .accessibilityIdentifier("Settings_BLEKeepAliveDebugToggle")
            }

            Text("Firmware debug aid. Keeps the BLE link open instead of dropping it after each sync, so hardware debugging sessions stay connected. Turn OFF for normal battery-saving sync.")
                .font(.system(size: 12))
                .foregroundStyle(theme.colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        .onChange(of: keepAliveEnabled) { _, newValue in
            // 仅在与当前生效值不同时落库，避免 .task 初始化把"未设置的默认值"写成"用户显式设置"
            // （否则以后改默认策略就区分不出这个用户是默认还是手动）。
            guard newValue != bleService.keepAliveDebugMode else { return }
            bleService.keepAliveDebugMode = newValue
            // 打开时若当前未连接，立刻尝试重连到上次设备，让调试连接尽快建立。
            if newValue, !bleService.connectionState.isConnected {
                Task { await bleService.attemptAutoReconnect() }
            }
        }
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

    // 失败状态必须用户可见：lastSyncTime 只在成功时更新，连续失败时硬件显示旧数据，
    // 用户只看到一个越来越旧的时间戳——没有这张卡，"同步失败"与"还没到同步窗口"不可区分。
    @MainActor
    private var syncStatusCard: some View {
        let failed = bleService.lastSyncFailed
        let lastSyncText: String
        if let lastSync = bleService.lastSyncTime {
            lastSyncText = Self.relativeFormatter.localizedString(for: lastSync, relativeTo: Date())
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
        .background(Color.white)
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

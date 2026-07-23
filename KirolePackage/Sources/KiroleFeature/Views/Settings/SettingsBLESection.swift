import SwiftUI

// MARK: - BLE Details Section

public struct SettingsBLESection: View {
    @Environment(ThemeManager.self) private var theme
    @State private var energyBottles: Int = 0
    @State private var bleService = BLEService.shared
    @State private var otaCoordinator = BLEOTACoordinator.shared
    @State private var wifiDebugCoordinator = BLEWiFiDebugCoordinator.shared
    @State private var trustedDeviceCount: Int = 0
    @State private var blockedDeviceCount: Int = 0
    @State private var showClearIdentityConfirmation = false
    @State private var showOTAUpgradeConfirmation = false
    @State private var keepAliveEnabled = false
    @State private var screenSize: ScreenSize = .fourInch

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "Hardware Details")

            bleModeCard
            syncStatusCard
            trustedDevicesCard
            currentSceneCard
            screenSizeCard
            otaUpgradeCard

            // 固件联调开关：DEBUG 包恒显示；Release 包仅 TestFlight 显示；正式上架包隐藏。
            if AppBuildEnvironment.showsHardwareDebugTools {
                wifiDebugCard
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
            if AppBuildEnvironment.showsHardwareDebugTools,
               bleService.connectionState.isConnected {
                await wifiDebugCoordinator.queryStatus()
            }
        }
        .alert("Clear Trusted Devices?", isPresented: $showClearIdentityConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                Task { await clearTrustedDevices() }
            }
        } message: {
            Text("This removes remembered and blocked BLE devices. Use it when switching hardware boards during integration.")
        }
        .alert("Update Firmware?", isPresented: $showOTAUpgradeConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Update") {
                Task { @MainActor in
                    if case .failed = otaCoordinator.state { otaCoordinator.reset() }
                    await otaCoordinator.requestReboot()
                }
            }
        } message: {
            Text("The device will restart and apply the staged update.bin (about 20 seconds). Make sure update.bin was uploaded via the device WiFi AP first.")
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
        .background(theme.colors.cardBackground)
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
        .background(theme.colors.cardBackground)
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
    private var otaUpgradeCard: some View {
        let otaState = otaCoordinator.state
        let hasFocusSession = FocusSessionService.shared.activeSession != nil
        let isConnected = bleService.connectionState.isConnected
        let isBusy = otaState == .sending || otaState == .awaitingReboot
        let isDisabled: Bool = {
            if hasFocusSession { return true }
            switch otaState {
            // 0x18 需要活跃连接才能送达；断连时禁用，防止点击后悬在 Sending...
            case .idle, .failed: return !isConnected
            case .sending, .awaitingReboot: return true
            }
        }()

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.colors.accent)
                Text("Firmware Update")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.colors.primaryText)
                Spacer()
                otaStateBadge(otaState)
            }

            Text(otaDescriptionText(otaState, hasFocusSession: hasFocusSession))
                .font(.system(size: 12))
                .foregroundStyle(theme.colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                // 防误触：0x18 一发出去设备就重启升级，先弹确认再执行。
                showOTAUpgradeConfirmation = true
            } label: {
                HStack(spacing: 8) {
                    if isBusy {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(theme.colors.primaryText)
                    }
                    Text(otaButtonLabel(otaState))
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(isDisabled ? theme.colors.secondaryText : theme.colors.primaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                // 禁用底走 border token（原 gray.opacity(0.08)）。
                .background(isDisabled ? theme.colors.border : theme.colors.accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(isDisabled || isBusy)
            .accessibilityLabel(isBusy ? "Firmware upgrade in progress" : "Update firmware")
            .accessibilityIdentifier("Settings_OTAUpgradeButton")
        }
        .padding(16)
        .background(theme.colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }

    private func otaStateBadge(_ state: BLEOTACoordinator.State) -> some View {
        let (label, color): (String, Color) = switch state {
        case .idle:           ("Ready", theme.colors.accent)
        case .sending:        ("Sending...", Color.orange)
        case .awaitingReboot: ("Upgrading...", Color.orange)
        case .failed:         ("Failed", Color.red)
        }
        return Text(label)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func otaDescriptionText(
        _ state: BLEOTACoordinator.State,
        hasFocusSession: Bool
    ) -> String {
        if hasFocusSession {
            return "Focus session in progress. End your focus session before updating firmware."
        }
        let isConnected = bleService.connectionState.isConnected
        switch state {
        case .idle:
            if let outcome = otaCoordinator.lastOutcome {
                switch outcome {
                case .confirmed(let from, let to):
                    if let from {
                        return "Upgrade complete — device is now on v\(to) (was v\(from))."
                    }
                    return "Upgrade complete — device is now on v\(to)."
                case .sameVersion(let version):
                    return "Device reconnected on the same firmware (v\(version)). The update may not have been applied — check the staged update.bin."
                case .versionUnknown:
                    return "Device reconnected, but did not report a firmware version."
                }
            }
            if !isConnected {
                return "Connect your Kirole device to update its firmware."
            }
            if let firmware = bleService.deviceFirmwareVersion {
                return "Device firmware v\(firmware). Upload update.bin via the device WiFi AP first, then tap Update. The device will reboot (~20 seconds)."
            }
            return "Upload update.bin via the device WiFi AP first, then tap Update. The device will reboot (~20 seconds)."
        case .sending:
            return "Sending upgrade command to device..."
        case .awaitingReboot:
            return "Device is upgrading firmware (~20 seconds). Do not close this screen."
        case .failed(let failure):
            let text: String = switch failure {
            case .deviceRejected(let code):
                "Device rejected upgrade (code 0x\(String(format: "%02X", code))). Check that update.bin was uploaded via WiFi AP."
            case .noResponse:
                "Device did not respond. Check the BLE connection and try again."
            case .timedOutWaitingForReboot:
                "Device did not reconnect after the expected upgrade window. Check the device."
            }
            // Retry 需要连接；断连时补一句原因，解释按钮为何是灰的。
            if !isConnected, failure != .noResponse {
                return text + " Reconnect your device to retry."
            }
            return text
        }
    }

    private func otaButtonLabel(_ state: BLEOTACoordinator.State) -> String {
        switch state {
        case .idle:           "Update Firmware"
        case .sending:        "Sending..."
        case .awaitingReboot: "Upgrading... (~20s)"
        case .failed:         "Retry"
        }
    }

    @MainActor
    private var wifiDebugCard: some View {
        let isConnected = bleService.connectionState.isConnected
        let isDisabled = !isConnected || wifiDebugCoordinator.isBusy
        let toggleBinding = Binding(
            get: { wifiDebugCoordinator.isEnabled },
            set: { newValue in
                Task { @MainActor in
                    await wifiDebugCoordinator.setEnabled(newValue)
                }
            }
        )

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "wifi.router")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(wifiDebugCoordinator.isEnabled ? Color.orange : theme.colors.secondaryText)

                Text("Wi-Fi PC Debug")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.colors.primaryText)

                Spacer()

                if wifiDebugCoordinator.isBusy {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(Color.orange)
                        .accessibilityLabel("Sending Wi-Fi debug command")
                }

                Toggle("", isOn: toggleBinding)
                    .labelsHidden()
                    .tint(Color.orange)
                    .disabled(isDisabled)
                    .accessibilityLabel("Wi-Fi PC Debug")
                    .accessibilityHint("Starts or stops the device Wi-Fi access point for PC debugging")
                    .accessibilityIdentifier("Settings_WiFiPCDebugToggle")
            }

            Text(wifiDebugDescription(isConnected: isConnected))
                .font(.system(size: 12))
                .foregroundStyle(wifiDebugCoordinator.failure == nil ? theme.colors.secondaryText : Color.red)
                .fixedSize(horizontal: false, vertical: true)

            if wifiDebugCoordinator.isEnabled {
                Text("On your PC, connect to the device hotspot, then open http://192.168.4.1/.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.colors.primaryText)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("Settings_WiFiPCDebugAddress")
            }
        }
        .padding(16)
        .background(theme.colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Settings_WiFiPCDebugCard")
    }

    private func wifiDebugDescription(isConnected: Bool) -> String {
        if !isConnected {
            return "Connect your Kirole device over BLE to control its Wi-Fi debug access point."
        }
        if let failure = wifiDebugCoordinator.failure {
            return failure.message
        }
        if wifiDebugCoordinator.isQuerying {
            return "Checking the device Wi-Fi debug status..."
        }
        switch wifiDebugCoordinator.state {
        case .unknown:
            return "Wi-Fi debug status is unknown. Reopen Hardware Details to query it."
        case .off:
            return "Starts the device SoftAP for PC debugging while keeping BLE connected."
        case .enabling:
            return "Starting the device Wi-Fi debug access point..."
        case .on:
            return "The device Wi-Fi debug access point is running."
        case .disabling:
            return "Stopping the device Wi-Fi debug access point..."
        case .failed:
            return "The Wi-Fi debug command failed. Toggle again to retry."
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
        .background(theme.colors.cardBackground)
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
        .background(theme.colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }
    #endif
}

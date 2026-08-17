#if KIROLE_INTERNAL
import SwiftUI
import KiroleFeature

struct InternalSettingsSection: View {
    @Environment(\.themeManager) private var theme
    @Environment(\.focusService) private var focusService
    @State private var bleService = BLEService.shared
    @State private var otaCoordinator = BLEOTACoordinator.shared
    @State private var wifiDebugCoordinator = BLEWiFiDebugCoordinator.shared
    @State private var shippingModeCoordinator = BLEShippingModeCoordinator.shared
    @State private var guardService = ScreenTimeFocusGuardService.shared
    @State private var testSessionCoordinator = FocusTestSessionCoordinator()
    @State private var showOTAUpgradeConfirmation = false
    @State private var showShippingModeConfirmation = false
    @State private var keepAliveEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "Internal Tools")

            bleModeCard
            otaUpgradeCard
            wifiDebugCard
            keepAliveCard
            shippingModeCard
            debugSessionButton
        }
        .task {
            keepAliveEnabled = bleService.keepAliveDebugMode
            if bleService.connectionState.isConnected {
                await wifiDebugCoordinator.queryStatus()
            }
        }
        .onChange(of: guardService.isPickerPresented) { wasPresented, isPresented in
            guard wasPresented, !isPresented else { return }
            Task {
                await testSessionCoordinator.resumeAfterPickerDismissal()
            }
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
        .alert("Enable Shipping Mode?", isPresented: $showShippingModeConfirmation) {
            Button("Cancel", role: .cancel) {}
                .accessibilityLabel("Cancel shipping mode")
                .accessibilityIdentifier("Settings_CancelShippingMode")
            Button("Enable", role: .destructive) {
                Task { @MainActor in
                    await shippingModeCoordinator.enable()
                }
            }
            .accessibilityLabel("Confirm shipping mode")
            .accessibilityIdentifier("Settings_ConfirmShippingMode")
        } message: {
            Text("The device will shut down and disconnect. To wake it again, hold the power button for 10 seconds or connect USB power for 10 seconds. Shipping mode turns off after wake-up.")
        }
        .alert(
            "Couldn't Start Focus",
            isPresented: Binding(
                get: { testSessionCoordinator.failureMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        testSessionCoordinator.dismissFailure()
                    }
                }
            )
        ) {
            Button("OK") {
                testSessionCoordinator.dismissFailure()
            }
        } message: {
            Text(testSessionCoordinator.failureMessage ?? "")
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
        .internalToolCard(theme: theme)
    }

    private var otaUpgradeCard: some View {
        let otaState = otaCoordinator.state
        let hasFocusSession = focusService.activeSession != nil
        let isConnected = bleService.connectionState.isConnected
        let isBusy = otaState == .sending || otaState == .awaitingReboot
        let shippingModeInProgress = shippingModeCoordinator.blocksAutomaticBLEWork
        let isDisabled: Bool = {
            if hasFocusSession || shippingModeInProgress { return true }
            switch otaState {
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
                .background(isDisabled ? theme.colors.border : theme.colors.accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(isDisabled || isBusy)
            .accessibilityLabel(isBusy ? "Firmware upgrade in progress" : "Update firmware")
            .accessibilityIdentifier("Settings_OTAUpgradeButton")
        }
        .internalToolCard(theme: theme)
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
        .internalToolCard(theme: theme)
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

    private var shippingModeCard: some View {
        let isConnected = bleService.connectionState.isConnected
        let isBusy = shippingModeCoordinator.state == .sending
            || shippingModeCoordinator.state == .awaitingDisconnect
        let otaInProgress = otaCoordinator.isBusy
        let hasFocusSession = focusService.activeSession != nil

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.red)

                Text("Shipping Mode (Factory)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.colors.primaryText)

                Spacer()

                if isBusy {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(Color.red)
                }
            }

            Text(shippingModeDescription(
                isConnected: isConnected,
                hasFocusSession: hasFocusSession
            ))
                .font(.system(size: 12))
                .foregroundStyle(shippingModeTextColor)
                .fixedSize(horizontal: false, vertical: true)

            Button(role: .destructive) {
                showShippingModeConfirmation = true
            } label: {
                Text(isBusy ? "Waiting for Device..." : "Enable Shipping Mode")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.red)
            .disabled(!isConnected || isBusy || otaInProgress || hasFocusSession)
            .accessibilityLabel(isBusy ? "Shipping mode activation in progress" : "Enable shipping mode")
            .accessibilityHint("Puts the device into factory shipping mode after confirmation")
            .accessibilityIdentifier("Settings_EnableShippingMode")
        }
        .internalToolCard(theme: theme)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Settings_ShippingModeCard")
    }

    private var shippingModeTextColor: Color {
        if case .failed = shippingModeCoordinator.state {
            return .red
        }
        return theme.colors.secondaryText
    }

    private func shippingModeDescription(isConnected: Bool, hasFocusSession: Bool) -> String {
        if hasFocusSession {
            return "End the active focus session before enabling factory shipping mode."
        }
        switch shippingModeCoordinator.state {
        case .idle:
            return isConnected
                ? "Factory only. The device will shut down and disconnect immediately."
                : "Connect your Kirole device before enabling factory shipping mode."
        case .sending:
            return "Sending the factory shipping-mode command..."
        case .awaitingDisconnect:
            return "Command sent. Waiting for the device to disconnect and confirm activation..."
        case .activated:
            return "Shipping mode is active. Hold the power button for 10 seconds or connect USB power for 10 seconds to wake the device."
        case .failed(.sendFailed):
            return "The command could not be sent. Check the BLE connection and try again."
        case .failed(.didNotDisconnect):
            return "The device did not disconnect, so the App cannot confirm shipping mode. Try again or check the firmware."
        case .failed(.activationUnconfirmed):
            return "The BLE connection was closed by the App, so shipping mode was not confirmed. Reconnect and try again."
        case .failed(.conflictingDeviceOperation):
            return "End the active focus session or wait for the firmware update before enabling shipping mode."
        }
    }

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
        .internalToolCard(theme: theme)
        .onChange(of: keepAliveEnabled) { _, newValue in
            guard newValue != bleService.keepAliveDebugMode else { return }
            bleService.keepAliveDebugMode = newValue
            if newValue, !bleService.connectionState.isConnected {
                Task { await bleService.attemptAutoReconnect() }
            }
        }
    }

    private var debugSessionButton: some View {
        Button {
            Task { @MainActor in
                await testSessionCoordinator.toggleTestSession()
            }
        } label: {
            HStack {
                Image(systemName: "timer")
                Text(
                    focusService.activeSession == nil
                    ? testSessionCoordinator.isBusy
                        ? "Preparing Focus..."
                        : "Start Test Focus Session"
                    : "End Test Focus Session"
                )
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(theme.colors.accent)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(testSessionCoordinator.isBusy)
        .accessibilityLabel("Start or end a real test focus session")
        .accessibilityHint("Opens the real focus screen with debugging controls")
        .accessibilityIdentifier("Debug_TestFocusSession")
    }

}

private extension View {
    func internalToolCard(theme: ThemeManager) -> some View {
        self
            .padding(16)
            .background(theme.colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }
}
#endif

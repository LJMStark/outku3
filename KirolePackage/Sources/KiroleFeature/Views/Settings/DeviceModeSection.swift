import SwiftUI

// MARK: - Device Section

/// 设备模式设置区域
public struct DeviceModeSection: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var bleService = BLEService.shared
    @State private var scanError: String?
    @State private var isScanButtonPressed = false
    @State private var scannedDevices: [BLEDevice] = []
    @State private var connectingDeviceID: UUID?

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader

            VStack(spacing: 12) {
                deviceCard

                if !bleService.connectionState.isConnected {
                    connectionAction

                    if !visibleDevices.isEmpty {
                        discoveredDeviceList
                    }
                }
            }
        }
    }

    private var sectionHeader: some View {
        Text("Device")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(theme.colors.primaryText)
    }

    private var deviceCard: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "5A7D6A"), Color(hex: "4A6352")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Texture overlay (optional)
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.black.opacity(0.1))
                .blendMode(.multiply)

            HStack(spacing: 8) {
                // Pet Image
                Image(appState.userProfile.companionCharacter.heroAssetName(variant: .main), bundle: .module)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 120)
                    .offset(y: 10)
                    .accessibilityLabel("Pet avatar")
                    .accessibilityIdentifier("Settings_DevicePetAvatar")

                VStack(alignment: .trailing, spacing: 12) {
                    batteryIndicator

                    if !appState.currentPetDialogue.isEmpty {
                        speechBubble
                    } else {
                        Spacer().frame(height: 0)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .frame(height: 140)
        .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .onTapGesture {
            guard canStartScan else { return }
            Task { await scanForDevices() }
        }
    }

    private var batteryIndicator: some View {
        HStack(spacing: 4) {
            let level = bleService.deviceBatteryLevel
            let filledCount = level.map { Int($0 / 10) } ?? 0
            HStack(spacing: 2) {
                ForEach(0..<10) { i in
                    Circle()
                        .fill(i < filledCount ? Color.white : Color.white.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
            Text(level.map { "\($0)%" } ?? "—")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
        }
        .accessibilityLabel(bleService.deviceBatteryLevel.map { "Device battery \($0)%" } ?? "Device battery unknown")
        .accessibilityIdentifier("Settings_BatteryIndicator")
    }

    private var speechBubble: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(hex: "C6D8C8"))

            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: "95B19A"), lineWidth: 4)

            Text(appState.currentPetDialogue)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Color(hex: "374151"))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .minimumScaleFactor(0.8)
                .lineLimit(3)
        }
    }

    private var connectionAction: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    Task { await scanForDevices() }
                } label: {
                    HStack(spacing: 8) {
                        if isScanInFlight {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else {
                            Image(systemName: connectionActionIcon)
                                .font(.system(size: 14, weight: .semibold))
                        }

                        Text(connectionActionTitle)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(canStartScan ? theme.colors.accent : theme.colors.secondaryText.opacity(0.45))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Scan for Kirole hardware")
                .accessibilityIdentifier("Settings_DeviceFindHardware")
                .disabled(!canStartScan)

                if bleService.connectionState.isConnected {
                    Button {
                        bleService.disconnect()
                        scannedDevices = []
                        scanError = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(theme.colors.secondaryText)
                            .frame(width: 38, height: 38)
                            .background(Color.white)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Disconnect hardware")
                    .accessibilityIdentifier("Settings_DeviceDisconnect")
                }
            }

            Text(connectionStatusText)
                .font(.system(size: 12))
                .foregroundStyle(theme.colors.secondaryText)

            if let scanError {
                Text(scanError)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        }
    }

    private var discoveredDeviceList: some View {
        VStack(spacing: 8) {
            ForEach(visibleDevices) { device in
                Button {
                    Task { await connect(to: device) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "display")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(theme.colors.accent)
                            .frame(width: 34, height: 34)
                            .background(theme.colors.accentLight)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(theme.colors.primaryText)

                            Text("\(device.rssi) dBm")
                                .font(.system(size: 11))
                                .foregroundStyle(theme.colors.secondaryText)
                        }

                        Spacer()

                        if connectingDeviceID == device.id {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Connect")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(theme.colors.accent)
                        }
                    }
                    .padding(12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.04), radius: 6, y: 3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Connect to \(device.name)")
                .accessibilityIdentifier("Settings_DeviceConnect_\(device.id.uuidString)")
                .disabled(connectingDeviceID != nil)
            }
        }
    }

    private var visibleDevices: [BLEDevice] {
        let devices = bleService.discoveredDevices.isEmpty ? scannedDevices : bleService.discoveredDevices
        return devices.reduce(into: [BLEDevice]()) { result, device in
            if !result.contains(where: { $0.id == device.id }) {
                result.append(device)
            }
        }
    }

    private var canStartScan: Bool {
        guard connectingDeviceID == nil else { return false }

        switch bleService.connectionState {
        case .connected, .scanning, .connecting:
            return false
        default:
            return !isScanButtonPressed
        }
    }

    private var isScanInFlight: Bool {
        if isScanButtonPressed { return true }

        switch bleService.connectionState {
        case .scanning, .connecting:
            return true
        default:
            return false
        }
    }

    private var connectionActionIcon: String {
        switch bleService.connectionState {
        case .error:
            return "arrow.clockwise"
        default:
            return "wave.3.right"
        }
    }

    private var connectionActionTitle: String {
        if isScanButtonPressed { return "Searching..." }

        switch bleService.connectionState {
        case .scanning:
            return "Searching..."
        case .connecting:
            return "Connecting..."
        case .connected:
            return "Connected"
        case .error:
            return "Search Again"
        case .disconnected:
            return visibleDevices.isEmpty ? "Find Kirole Device" : "Search Again"
        }
    }

    private var connectionStatusText: String {
        if let device = bleService.connectedDevice, bleService.connectionState.isConnected {
            return "Connected to \(device.name)."
        }

        if isScanInFlight {
            return "Searching nearby Kirole devices."
        }

        if !visibleDevices.isEmpty {
            return "Select a device below to connect."
        }

        switch bleService.connectionState {
        case .error(let message):
            return message
        default:
            return "Tap the card or button to search for hardware."
        }
    }

    private func scanForDevices() async {
        scanError = nil
        scannedDevices = []
        isScanButtonPressed = true
        defer { isScanButtonPressed = false }

        do {
            let devices = try await bleService.scanForDevices(timeout: 10)
            scannedDevices = devices
            if devices.isEmpty {
                scanError = "No Kirole device found nearby."
            }
        } catch {
            scanError = error.localizedDescription
        }
    }

    private func connect(to device: BLEDevice) async {
        scanError = nil
        connectingDeviceID = device.id
        bleService.stopScanning()
        defer { connectingDeviceID = nil }

        do {
            try await bleService.connect(to: device)
            scannedDevices = []
        } catch {
            scanError = error.localizedDescription
        }
    }
}

#Preview {
    DeviceModeSection()
        .padding()
        .environment(AppState.shared)
        .environment(ThemeManager.shared)
}

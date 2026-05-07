import SwiftUI

// MARK: - BLE / Device Section

public struct SettingsBLESection: View {
    @Environment(ThemeManager.self) private var theme
    @State private var energyBottles: Int = 0
    @State private var bleService = BLEService.shared
    @State private var scanError: String?

    public init() {}

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "Device")

            deviceStatusCard

            bleModeCard
            currentSceneCard

            #if DEBUG
            simulatorStatusCard
            #endif
        }
        .task {
            energyBottles = await LocalStorage.shared.loadEnergyBottles()
        }
    }

    private var deviceStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(theme.colors.accentLight)
                        .frame(width: 80, height: 100)
                    Image(systemName: bleService.connectionState.isConnected ? "display" : "display.trianglebadge.exclamationmark")
                        .font(.system(size: 28))
                        .foregroundStyle(
                            bleService.connectionState.isConnected
                            ? theme.colors.accent
                            : theme.colors.secondaryText.opacity(0.5)
                        )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(deviceTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.colors.primaryText)

                    Text(deviceSubtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    if let error = scanError {
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                    }
                }

                Spacer(minLength: 0)
            }

            if !bleService.connectionState.isConnected {
                Button {
                    Task { await scanAndConnect() }
                } label: {
                    HStack(spacing: 6) {
                        if case .scanning = bleService.connectionState {
                            ProgressView().controlSize(.small)
                        } else if case .connecting = bleService.connectionState {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "wave.3.right")
                        }
                        Text(scanButtonTitle)
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(theme.colors.accent)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("扫描并连接设备")
                .accessibilityIdentifier("Settings_BLEScan")
                .disabled(isScanInFlight)
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }

    private var deviceTitle: String {
        if let device = bleService.connectedDevice, bleService.connectionState.isConnected {
            return device.name
        }
        return "E-ink Device"
    }

    private var deviceSubtitle: String {
        switch bleService.connectionState {
        case .connected:
            if let last = bleService.lastSyncTime {
                return "Last synced \(Self.relativeFormatter.localizedString(for: last, relativeTo: Date()))"
            }
            return "Connected · awaiting first sync"
        case .scanning:
            return "Scanning for nearby devices…"
        case .connecting:
            return "Connecting…"
        case .error(let message):
            return message
        case .disconnected:
            return "No device paired"
        }
    }

    private var scanButtonTitle: String {
        switch bleService.connectionState {
        case .scanning: return "Scanning…"
        case .connecting: return "Connecting…"
        default: return "Scan for device"
        }
    }

    private var isScanInFlight: Bool {
        switch bleService.connectionState {
        case .scanning, .connecting: return true
        default: return false
        }
    }

    private func scanAndConnect() async {
        scanError = nil
        do {
            let devices = try await bleService.scanForDevices(timeout: 10)
            guard let first = devices.first else {
                scanError = "No Kirole device found nearby."
                return
            }
            try await bleService.connect(to: first)
        } catch {
            scanError = error.localizedDescription
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


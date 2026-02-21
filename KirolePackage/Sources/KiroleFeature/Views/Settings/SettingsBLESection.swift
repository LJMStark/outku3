import SwiftUI

// MARK: - BLE / Device Section

public struct SettingsBLESection: View {
    @Environment(ThemeManager.self) private var theme

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "Device")

            RoundedRectangle(cornerRadius: 24)
                .fill(Color.white)
                .frame(height: 200)
                .overlay {
                    VStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(theme.colors.accentLight)
                            .frame(width: 120, height: 160)
                            .overlay {
                                VStack(spacing: 8) {
                                    Image(systemName: "display")
                                        .font(.system(size: 40))
                                        .foregroundStyle(theme.colors.secondaryText.opacity(0.5))
                                    Text("E-ink Device")
                                        .font(.system(size: 12))
                                        .foregroundStyle(theme.colors.secondaryText.opacity(0.5))
                                }
                            }
                    }
                }
                .shadow(color: .black.opacity(0.05), radius: 8, y: 4)

            bleModeCard
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
}

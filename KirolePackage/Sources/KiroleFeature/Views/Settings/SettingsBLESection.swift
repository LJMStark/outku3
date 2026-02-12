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
        }
    }
}

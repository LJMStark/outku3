import SwiftUI

// MARK: - Theme Section

public struct SettingsThemeSection: View {
    @Environment(ThemeManager.self) private var themeManager

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "Theme")

            VStack(spacing: 12) {
                ForEach(AppTheme.allCases) { themeOption in
                    ThemeOptionRow(
                        theme: themeOption,
                        isSelected: themeManager.currentTheme == themeOption
                    ) {
                        withAnimation(Animation.appStandard) {
                            themeManager.setTheme(themeOption)
                        }
                    }
                }
            }
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        }
    }
}

// MARK: - Theme Option Row

private struct ThemeOptionRow: View {
    let theme: AppTheme
    let isSelected: Bool
    let action: () -> Void

    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        Button(action: action) {
            HStack {
                Text(theme.rawValue)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(hex: "374151"))

                Spacer()

                // Color preview dots
                HStack(spacing: 6) {
                    ForEach(theme.previewColors, id: \.self) { color in
                        Circle()
                            .fill(color)
                            .frame(width: 20, height: 20)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 2)
                            )
                            .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
                    }
                }

                // Toggle
                SettingsToggleSwitch(isOn: isSelected)
            }
            .padding(16)
            .background(Color(hex: "F9FAFB"))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color(hex: "D1D5DB") : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

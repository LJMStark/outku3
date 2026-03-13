import SwiftUI

// MARK: - Theme Section

public struct SettingsThemeSection: View {
    @Environment(ThemeManager.self) private var themeManager

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Theme")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(themeManager.colors.primaryText)

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
                            .frame(width: 16, height: 16)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color.white)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.black : Color(hex: "E5E7EB"), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

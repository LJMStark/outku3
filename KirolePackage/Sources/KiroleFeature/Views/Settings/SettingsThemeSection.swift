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
                        withAnimation(.kiroleGentle) {
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
                    .foregroundStyle(themeManager.colors.primaryText)

                Spacer()

                // Color preview dots
                HStack(spacing: 6) {
                    ForEach(theme.previewColors, id: \.self) { color in
                        Circle()
                            .fill(color)
                            .frame(width: 16, height: 16)
                            .accessibilityHidden(true)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(themeManager.colors.cardBackground)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    // 选中描边用主题 accent 而非纯黑：在紫/青主题下黑色描边
                    // 与色板毫无关系；accent 让"选中"与预览色点形成呼应。
                    .stroke(
                        isSelected ? themeManager.colors.accent : themeManager.colors.border,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSelected ? "Current theme: \(theme.rawValue)" : "Switch to \(theme.rawValue) theme")
        .accessibilityIdentifier("Settings_Theme_\(theme.rawValue)")
    }
}

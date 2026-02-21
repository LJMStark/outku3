import SwiftUI

public struct ThemePreviewCard: View {
    let theme: AppTheme
    let isSelected: Bool
    let action: () -> Void

    public init(theme: AppTheme, isSelected: Bool, action: @escaping () -> Void) {
        self.theme = theme
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(theme.colors.background)

                    VStack(spacing: 8) {
                        Circle()
                            .fill(theme.colors.primary)
                            .frame(width: 32, height: 32)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(theme.colors.secondaryText.opacity(0.3))
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(theme.colors.secondaryText.opacity(0.3))
                            .frame(width: 60, height: 8)
                    }
                    .padding(8)
                }
                .frame(width: 96, height: 128)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(.white, lineWidth: 4)
                    }
                }
            }
            .scaleEffect(isSelected ? 1.05 : 1.0)
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            .animation(Animation.appStandard, value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

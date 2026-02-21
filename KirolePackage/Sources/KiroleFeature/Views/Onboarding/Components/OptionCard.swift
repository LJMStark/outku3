import SwiftUI

public struct OptionCard: View {
    @Environment(ThemeManager.self) private var theme

    let label: String
    let emoji: String?
    let sfSymbol: String?
    let isSelected: Bool
    let action: () -> Void

    public init(label: String, emoji: String? = nil, sfSymbol: String? = nil, isSelected: Bool, action: @escaping () -> Void) {
        self.label = label
        self.emoji = emoji
        self.sfSymbol = sfSymbol
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                if let sfSymbol = sfSymbol {
                    ZStack {
                        Circle()
                            .fill(isSelected ? theme.colors.primary : theme.colors.background)
                            .frame(width: 40, height: 40)

                        Image(systemName: sfSymbol)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(isSelected ? .white : theme.colors.secondaryText)
                    }
                } else if let emoji = emoji {
                    Image(systemName: emoji)
                        .font(.system(size: 24))
                        .foregroundStyle(isSelected ? theme.colors.primary : theme.colors.secondaryText)
                        .frame(width: 40, height: 40)
                }

                Text(label)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(isSelected ? theme.colors.primary : theme.colors.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isSelected {
                    ZStack {
                        Circle()
                            .fill(theme.colors.primary)
                            .frame(width: 24, height: 24)

                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? theme.colors.accentLight : .white)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? theme.colors.primary : theme.colors.timeline, lineWidth: 2)
                    }
            }
        }
        .buttonStyle(.plain)
        .animation(Animation.appStandard, value: isSelected)
    }
}

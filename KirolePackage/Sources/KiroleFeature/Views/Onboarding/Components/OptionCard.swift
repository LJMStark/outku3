import SwiftUI

public struct OptionCard: View {
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

    private let tealColor = Color(hex: "0D8A6A")
    private let selectedBg = Color(hex: "F0FDF9")

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                if let sfSymbol = sfSymbol {
                    ZStack {
                        Circle()
                            .fill(isSelected ? tealColor : Color(hex: "F3F4F6"))
                            .frame(width: 40, height: 40)

                        Image(systemName: sfSymbol)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(isSelected ? .white : Color(hex: "6B7280"))
                    }
                } else if let emoji = emoji {
                    Image(systemName: emoji)
                        .font(.system(size: 24))
                        .foregroundStyle(isSelected ? tealColor : Color(hex: "6B7280"))
                        .frame(width: 40, height: 40)
                }

                Text(label)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(isSelected ? tealColor : Color(hex: "1A1A2E"))
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isSelected {
                    ZStack {
                        Circle()
                            .fill(tealColor)
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
                    .fill(isSelected ? selectedBg : .white)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? tealColor : Color(hex: "E5E7EB"), lineWidth: 2)
                    }
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

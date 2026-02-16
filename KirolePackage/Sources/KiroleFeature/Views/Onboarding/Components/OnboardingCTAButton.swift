import SwiftUI

public struct OnboardingCTAButton: View {
    @Environment(ThemeManager.self) private var theme

    let title: String
    let emoji: String?
    let isEnabled: Bool
    let action: () -> Void

    public init(title: String, emoji: String? = nil, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.emoji = emoji
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                if let emoji = emoji {
                    Text(emoji)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
            }
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .foregroundStyle(isEnabled ? .white : theme.colors.secondaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background {
                Capsule()
                    .fill(isEnabled ? theme.colors.primaryText : theme.colors.timeline)
            }
            .shadow(color: .black.opacity(isEnabled ? 0.2 : 0), radius: 12, y: 6)
        }
        .buttonStyle(CTAButtonStyle())
        .disabled(!isEnabled)
    }
}

private struct CTAButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

import SwiftUI

struct ChoicePill: View {
    let title: String
    let action: () -> Void
    @Environment(ThemeManager.self) private var theme
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppTypography.headline)
                .foregroundStyle(Color.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background {
                    Capsule()
                        .fill(Color.white.opacity(0.1))
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

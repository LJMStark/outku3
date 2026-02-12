import SwiftUI

struct DialogBubble: View {
    let text: String
    let isTyping: Bool
    @Environment(ThemeManager.self) private var theme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(AppTypography.title2)
                .foregroundStyle(Color.white) // Start with white for contrast on dark bg
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.numericText()) // Subtle jitter
            
            if isTyping {
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle()
                            .fill(Color.white.opacity(0.5))
                            .frame(width: 6, height: 6)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.3))
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
    }
}

import SwiftUI

struct OnboardingStyleStep: View {
    @Environment(ThemeManager.self) private var theme
    let selectedStyle: CompanionStyle?
    let onSelect: (CompanionStyle) -> Void

    @State private var showContent = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Title
            Text("How should I support you?")
                .font(AppTypography.largeTitle)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 20)

            // 2x2 Grid of styles
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16)
            ], spacing: 16) {
                ForEach(CompanionStyle.allCases, id: \.self) { style in
                    StyleCard(
                        style: style,
                        isSelected: selectedStyle == style,
                        onTap: { onSelect(style) }
                    )
                }
            }
            .padding(.horizontal, 24)
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 30)

            Spacer()
            Spacer()
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.2)) {
                showContent = true
            }
        }
    }
}

private struct StyleCard: View {
    let style: CompanionStyle
    let isSelected: Bool
    let onTap: () -> Void

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                Image(systemName: style.iconName)
                    .font(.system(size: 32))
                    .foregroundStyle(isSelected ? theme.colors.accent : .white)

                Text(style.displayName)
                    .font(AppTypography.headline)
                    .foregroundStyle(.white)

                Text(style.description)
                    .font(AppTypography.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.white.opacity(isSelected ? 0.2 : 0.1))
                    .stroke(isSelected ? theme.colors.accent : .white.opacity(0.2), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

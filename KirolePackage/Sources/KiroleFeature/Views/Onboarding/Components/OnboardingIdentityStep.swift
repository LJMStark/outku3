import SwiftUI

struct OnboardingIdentityStep: View {
    @Environment(ThemeManager.self) private var theme
    let selectedWorkType: WorkType?
    let onSelect: (WorkType) -> Void

    // Show all types except .other
    private var workTypes: [WorkType] {
        WorkType.allCases.filter { $0 != .other }
    }

    @State private var showContent = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Title
            Text("Who are you?")
                .font(AppTypography.largeTitle)
                .foregroundStyle(.white)
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 20)

            // Grid of options
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16)
            ], spacing: 16) {
                ForEach(workTypes, id: \.self) { type in
                    IdentityCard(
                        type: type,
                        isSelected: selectedWorkType == type,
                        onTap: { onSelect(type) }
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

private struct IdentityCard: View {
    let type: WorkType
    let isSelected: Bool
    let onTap: () -> Void

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                Image(systemName: type.iconName)
                    .font(.system(size: 28))
                    .foregroundStyle(isSelected ? theme.colors.accent : .white)

                Text(type.displayName)
                    .font(AppTypography.caption)
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 100)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white.opacity(isSelected ? 0.2 : 0.1))
                    .stroke(isSelected ? theme.colors.accent : .white.opacity(0.2), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

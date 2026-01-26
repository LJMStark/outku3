import SwiftUI

struct OnboardingGoalsStep: View {
    @Environment(ThemeManager.self) private var theme
    let selectedGoals: Set<UserGoal>
    let onToggle: (UserGoal) -> Void
    let onContinue: () -> Void

    @State private var showContent = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Title
            VStack(spacing: 8) {
                Text("What brings you here?")
                    .font(AppTypography.largeTitle)
                    .foregroundStyle(.white)

                Text("Select up to 3")
                    .font(AppTypography.body)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 20)

            // Grid of goals
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16)
            ], spacing: 16) {
                ForEach(UserGoal.allCases, id: \.self) { goal in
                    GoalCard(
                        goal: goal,
                        isSelected: selectedGoals.contains(goal),
                        isDisabled: !selectedGoals.contains(goal) && selectedGoals.count >= 3,
                        onTap: { onToggle(goal) }
                    )
                }
            }
            .padding(.horizontal, 24)
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 30)

            Spacer()

            // Continue Button
            if !selectedGoals.isEmpty {
                Button(action: onContinue) {
                    Text("Continue")
                        .font(AppTypography.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            Capsule()
                                .fill(.white)
                        )
                }
                .padding(.horizontal, 40)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Spacer()
                .frame(height: 40)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedGoals.isEmpty)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.2)) {
                showContent = true
            }
        }
    }
}

private struct GoalCard: View {
    let goal: UserGoal
    let isSelected: Bool
    let isDisabled: Bool
    let onTap: () -> Void

    @Environment(ThemeManager.self) private var theme

    private var contentOpacity: Double {
        isDisabled ? 0.4 : 1.0
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                Image(systemName: goal.iconName)
                    .font(.system(size: 24))
                    .foregroundStyle(isSelected ? theme.colors.accent : .white.opacity(contentOpacity))

                Text(goal.displayName)
                    .font(AppTypography.caption)
                    .foregroundStyle(.white.opacity(isDisabled ? 0.4 : 0.9))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 90)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white.opacity(isSelected ? 0.2 : 0.1))
                    .stroke(isSelected ? theme.colors.accent : .white.opacity(isDisabled ? 0.1 : 0.2), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

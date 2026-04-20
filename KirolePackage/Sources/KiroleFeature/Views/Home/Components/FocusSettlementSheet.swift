import SwiftUI

// MARK: - Focus Settlement Sheet

public struct FocusSettlementSheet: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dismiss) private var dismiss

    let focusMinutes: Int
    let earnedBottles: Int
    let totalBottles: Int
    let unlockedNewScene: Bool

    @State private var displayedBottles: Int = 0
    @State private var showContent = false

    public init(
        focusMinutes: Int,
        earnedBottles: Int,
        totalBottles: Int,
        unlockedNewScene: Bool = false
    ) {
        self.focusMinutes = focusMinutes
        self.earnedBottles = earnedBottles
        self.totalBottles = totalBottles
        self.unlockedNewScene = unlockedNewScene
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.gray.opacity(0.4))
                .frame(width: 40, height: 5)
                .padding(.top, 12)
                .padding(.bottom, 28)

            // Title
            Text("Focus Complete")
                .font(.system(size: 24, weight: .bold, design: .serif))
                .foregroundStyle(theme.colors.primaryText)
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 20)

            Spacer().frame(height: 32)

            // Duration
            HStack(spacing: 8) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(hex: "4A6B53"))

                Text("\(focusMinutes) minutes")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(theme.colors.primaryText)
            }
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 15)

            Spacer().frame(height: 32)

            // Energy bottles earned
            VStack(spacing: 12) {
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(index < earnedBottles ? Color(hex: "4A6B53") : Color(hex: "C8E6C9"))
                            .frame(width: 20, height: 20)
                            .shadow(
                                color: index < earnedBottles ? Color(hex: "4A6B53").opacity(0.4) : .clear,
                                radius: 6
                            )
                    }
                }

                Text("+\(displayedBottles) energy")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: "4A6B53"))
                    .contentTransition(.numericText())
            }
            .opacity(showContent ? 1 : 0)
            .scaleEffect(showContent ? 1 : 0.8)

            Spacer().frame(height: 16)

            // Total
            Text("Total: \(totalBottles) bottles")
                .font(.system(size: 14))
                .foregroundStyle(theme.colors.secondaryText)
                .opacity(showContent ? 1 : 0)

            // New scene unlock banner
            if unlockedNewScene {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.orange)

                    Text("New Scene Unlocked!")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.orange)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.orange.opacity(0.1))
                .clipShape(Capsule())
                .padding(.top, 20)
                .opacity(showContent ? 1 : 0)
                .scaleEffect(showContent ? 1 : 0.5)
            }

            Spacer()

            // Dismiss button
            Button {
                dismiss()
            } label: {
                Text("Continue")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(hex: "4A6B53"))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .opacity(showContent ? 1 : 0)
        }
        .background(theme.colors.background)
        .task {
            withAnimation(.kiroleSmooth) {
                showContent = true
            }

            // Animate bottle count from 0 to earned — each bump is a small
            // celebratory pop, so use the bouncy curve for emphasis.
            if earnedBottles > 0 {
                try? await Task.sleep(for: .milliseconds(400))
                for i in 1...earnedBottles {
                    withAnimation(.kiroleBouncy) {
                        displayedBottles = i
                    }
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
        }
    }
}

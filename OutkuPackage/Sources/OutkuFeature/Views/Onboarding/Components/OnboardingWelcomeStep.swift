import SwiftUI

struct OnboardingWelcomeStep: View {
    let onStart: () -> Void

    @State private var animationPhase = 0
    @State private var pulseAnimation = false

    private var showTitle: Bool { animationPhase >= 1 }
    private var showSubtitle: Bool { animationPhase >= 2 }
    private var showButton: Bool { animationPhase >= 3 }

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Main Title
            VStack(spacing: 16) {
                Text("Every day, a small step")
                    .font(AppTypography.largeTitle)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .opacity(showTitle ? 1 : 0)
                    .offset(y: showTitle ? 0 : 20)

                Text("becomes a giant leap")
                    .font(AppTypography.largeTitle)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .opacity(showTitle ? 1 : 0)
                    .offset(y: showTitle ? 0 : 20)
            }

            // Subtitle
            Text("Complete 3 tasks, watch your companion grow")
                .font(AppTypography.body)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .opacity(showSubtitle ? 1 : 0)
                .offset(y: showSubtitle ? 0 : 10)
                .padding(.horizontal, 40)

            Spacer()

            // Start Button
            Button(action: onStart) {
                Text("Begin Your Journey")
                    .font(AppTypography.headline)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 16)
                    .background(
                        Capsule()
                            .fill(.white)
                    )
                    .scaleEffect(pulseAnimation ? 1.02 : 1.0)
            }
            .opacity(showButton ? 1 : 0)
            .offset(y: showButton ? 0 : 20)
            .padding(.bottom, 60)
        }
        .task {
            await runAnimationSequence()
        }
    }

    private func runAnimationSequence() async {
        try? await Task.sleep(for: .seconds(0.3))
        withAnimation(.easeOut(duration: 0.8)) { animationPhase = 1 }

        try? await Task.sleep(for: .seconds(0.5))
        withAnimation(.easeOut(duration: 0.6)) { animationPhase = 2 }

        try? await Task.sleep(for: .seconds(0.4))
        withAnimation(.easeOut(duration: 0.6)) { animationPhase = 3 }

        try? await Task.sleep(for: .seconds(0.3))
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            pulseAnimation = true
        }
    }
}

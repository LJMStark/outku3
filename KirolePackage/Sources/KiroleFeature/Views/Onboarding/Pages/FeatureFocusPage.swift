import SwiftUI

public struct FeatureFocusPage: View {
    let onboardingState: OnboardingState

    public init(onboardingState: OnboardingState) {
        self.onboardingState = onboardingState
    }

    public var body: some View {
        ZStack {
            Color(hex: "0D8A6A").ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()
                    CharacterView(imageName: "blue-monster", size: 80)
                        .padding(.trailing, 16)
                }
                Spacer()
            }
            .padding(.top, 80)

            VStack(spacing: 0) {
                HStack {
                    SoundToggleButton(isEnabled: Binding(
                        get: { onboardingState.soundEnabled },
                        set: { onboardingState.soundEnabled = $0 }
                    ))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                ProgressDots(activeIndex: 1)
                    .padding(.top, 8)

                VStack(spacing: 8) {
                    Text("Focus, not frenzy \u{2728}")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Widget updates quietly -- no dings, no FOMO.")
                        .font(.system(size: 16, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.top, 24)

                BeforeAfterCard()
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .frame(maxHeight: .infinity)

                OnboardingCTAButton(title: "I will Focus", emoji: "\u{1F9D8}") {
                    onboardingState.goNext()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
    }
}

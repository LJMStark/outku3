import SwiftUI

public struct WelcomePage: View {
    let onboardingState: OnboardingState

    @State private var showDialog = false

    public init(onboardingState: OnboardingState) {
        self.onboardingState = onboardingState
    }

    public var body: some View {
        ZStack {
            Color(hex: "0D8A6A").ignoresSafeArea()

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

                ZStack {
                    FloatingIconRing()

                    Text("\u{1F60C}")
                        .font(.system(size: 80))
                        .scaleEffect(showDialog ? 1.0 : 0.0)
                        .opacity(showDialog ? 1.0 : 0.0)
                        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: showDialog)
                }
                .frame(maxHeight: .infinity)

                VStack(spacing: 24) {
                    if showDialog {
                        HStack(alignment: .bottom, spacing: 12) {
                            // TODO: Replace with Kirole pet asset
                            CharacterView(imageName: "inku-main", size: 96)
                            OnboardingDialogBubble(
                                text: "Hey there! I'm Kirole, your focus companion. Ready to unlock your flow?",
                                style: .light
                            )
                        }
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .opacity
                        ))
                    }

                    OnboardingCTAButton(title: "Let's Go!", emoji: "\u{2764}\u{FE0F}\u{200D}\u{1F525}") {
                        onboardingState.goNext()
                    }

                    Text("Already have an account?")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        .task {
            do {
                try await Task.sleep(for: .milliseconds(500))
                withAnimation(.easeOut(duration: 0.4)) {
                    showDialog = true
                }
            } catch { }
        }
    }
}

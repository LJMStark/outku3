import SwiftUI

public struct WelcomePage: View {
    let onboardingState: OnboardingState
    @Environment(ThemeManager.self) private var theme

    @State private var showDialog = false

    public init(onboardingState: OnboardingState) {
        self.onboardingState = onboardingState
    }

    public var body: some View {
        ZStack {
            theme.colors.primary.ignoresSafeArea()

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

                FloatingIconRing()
                    .frame(maxHeight: .infinity)

                VStack(spacing: 24) {
                    if showDialog {
                        HStack(alignment: .bottom, spacing: 12) {
                            CharacterView(
                                character: .joy,
                                size: 96
                            )
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
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        .task {
            do {
                try await Task.sleep(for: .milliseconds(500))
                withAnimation(.appleEaseOut) {
                    showDialog = true
                }
            } catch { }
        }
    }
}

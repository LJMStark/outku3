import SwiftUI

public struct PersonalizationPage: View {
    let onboardingState: OnboardingState
    @Environment(ThemeManager.self) private var themeManager

    @State private var selectedAvatar: AvatarChoice

    public init(onboardingState: OnboardingState) {
        self.onboardingState = onboardingState
        self._selectedAvatar = State(initialValue: onboardingState.profile.selectedAvatar ?? .inku)
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

                ProgressDots(activeIndex: 2)
                    .padding(.top, 8)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        Text("Your Inku, Your Way \u{1F3A8}")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        VStack(spacing: 16) {
                            Text("Pick your favorite mood")
                                .font(.system(size: 16, design: .rounded))
                                .foregroundStyle(.white.opacity(0.8))
                            HStack(spacing: 12) {
                                ForEach(AppTheme.allCases, id: \.self) { theme in
                                    ThemePreviewCard(
                                        theme: theme,
                                        isSelected: themeManager.currentTheme == theme
                                    ) {
                                        themeManager.setTheme(theme)
                                        onboardingState.profile.selectedTheme = theme.rawValue
                                    }
                                }
                            }
                        }

                        VStack(spacing: 16) {
                            Text("Pick an Inku Avatar")
                                .font(.system(size: 16, design: .rounded))
                                .foregroundStyle(.white.opacity(0.8))

                            AvatarSelector(selectedId: $selectedAvatar)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                }

                OnboardingCTAButton(title: "I'll Make It Mine", emoji: "\u{1F3A8}") {
                    onboardingState.profile.selectedAvatar = selectedAvatar
                    onboardingState.goNext()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
    }
}

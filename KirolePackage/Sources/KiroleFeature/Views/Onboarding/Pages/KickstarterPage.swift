import SwiftUI

public struct KickstarterPage: View {
    let onboardingState: OnboardingState

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

                ProgressDots(activeIndex: 3)
                    .padding(.top, 8)

                VStack(spacing: 8) {
                    Text("Loved on every desk \u{1F58A}\u{FE0F}")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Born on Kickstarter, alive on your phone...and IRL.")
                        .font(.system(size: 16, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.top, 16)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        kickstarterCard
                        HStack(alignment: .bottom, spacing: 12) {
                            CharacterView(imageName: "inku-main", size: 64)
                            OnboardingDialogBubble(
                                text: "Inku here! I'm so excited to bring focus, clarity and joy to your day!",
                                style: .light
                            )
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                    }
                }

                OnboardingCTAButton(title: "Get Started") {
                    onboardingState.goNext()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
                .padding(.top, 16)
            }
        }
    }

    private var kickstarterCard: some View {
        VStack(spacing: 0) {
            ZStack {
                Image("kickstarter-card", bundle: .module)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 192)
                    .clipped()

                Circle()
                    .fill(.black.opacity(0.7))
                    .frame(width: 56, height: 56)
                    .overlay {
                        Image(systemName: "play.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                            .offset(x: 2)
                    }

                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                            Text("funded with KICKSTARTER")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(hex: "05CE78"))
                        .clipShape(Capsule())
                        .padding(8)
                    }
                    Spacer()
                    HStack {
                        ZStack {
                            Circle()
                                .fill(.black.opacity(0.8))
                                .frame(width: 48, height: 48)
                                .overlay {
                                    Circle().stroke(.white, lineWidth: 2)
                                }
                            Image(systemName: "heart.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.red)
                        }
                        .padding(8)
                        Spacer()
                    }
                }
            }
            .frame(height: 192)

            VStack(alignment: .leading, spacing: 8) {
                Text("Inku Calendar: Watch your day flicker to life")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: "1A1A2E"))

                HStack(spacing: 16) {
                    Label("Project We Love", systemImage: "heart")
                    Label("San Francisco, CA", systemImage: "mappin")
                    Label("Hardware", systemImage: "tag")
                }
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Color(hex: "6B7280"))

                HStack {
                    VStack(alignment: .leading) {
                        Text("$284,684")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(hex: "1A1A2E"))
                        Text("pledged of $15,000 goal")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(Color(hex: "6B7280"))
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("1,508")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(hex: "1A1A2E"))
                        Text("backers")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(Color(hex: "6B7280"))
                    }
                }
            }
            .padding(16)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
        .padding(.horizontal, 24)
    }
}

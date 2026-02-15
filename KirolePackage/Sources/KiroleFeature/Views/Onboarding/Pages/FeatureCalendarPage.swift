import SwiftUI

public struct FeatureCalendarPage: View {
    let onboardingState: OnboardingState

    @State private var visibleBoxes: Int = 0

    private let dialogBoxes: [(text: String, style: DialogBubbleStyle)] = [
        ("You have a coffee chat with someone named Anna at 1:30 PM - enjoy!", .light),
        ("Coffee with Anna! Maybe meet at the new spot we tried yesterday?", .accent),
        ("Been a while since you hung out with Anna - schedule a hang?", .dark),
    ]

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

                ProgressDots(activeIndex: 0)
                    .padding(.top, 8)

                VStack(spacing: 8) {
                    Text("Not Just a Calendar \u{1F604}")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Inku learns and grows with you")
                        .font(.system(size: 16, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.top, 24)
                VStack(spacing: 16) {
                    ForEach(Array(dialogBoxes.enumerated()), id: \.offset) { index, box in
                        if index < visibleBoxes {
                            OnboardingDialogBubble(text: box.text, style: box.style, showPointer: false)
                                .transition(.asymmetric(
                                    insertion: .move(edge: index % 2 == 0 ? .leading : .trailing).combined(with: .opacity),
                                    removal: .opacity
                                ))

                            if index < dialogBoxes.count - 1 && index < visibleBoxes - 1 {
                                Image(systemName: "arrow.down")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .frame(maxHeight: .infinity)

                HStack {
                    CharacterView(imageName: "inku-main", size: 80)
                    Spacer()
                }
                .padding(.horizontal, 16)

                OnboardingCTAButton(title: "Continue", emoji: "\u{1F44B}") {
                    onboardingState.goNext()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        .task {
            do {
                for i in 1...dialogBoxes.count {
                    try await Task.sleep(for: .milliseconds(200 + UInt64(i) * 200))
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        visibleBoxes = i
                    }
                }
            } catch { }
        }
    }
}

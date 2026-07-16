import SwiftUI

public struct FeatureCalendarPage: View {
    let onboardingState: OnboardingState
    @Environment(ThemeManager.self) private var theme

    @State private var visibleBoxes: Int = 0

    private let dialogBoxes: [(text: String, style: DialogBubbleStyle)] = [
        ("You have 'Write project proposal' -- big day! I'll cheer you on through it.", .light),
        ("Your standup is in 30 min -- want to review yesterday's notes first?", .accent),
        ("You've been crushing it today -- 3 tasks done, 2 to go!", .dark),
    ]

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

                ProgressDots(activeIndex: 0)
                    .padding(.top, 8)

                VStack(spacing: 8) {
                    Text("Pet who knows your day")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Kirole sees your tasks and meets you wherever you are in the day")
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
                    CharacterView(
                        character: .joy,
                        size: 80
                    )
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
                    withAnimation(.kiroleGentle) {
                        visibleBoxes = i
                    }
                }
            } catch { }
        }
    }
}

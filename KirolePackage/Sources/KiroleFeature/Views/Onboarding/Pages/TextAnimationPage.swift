import SwiftUI

public struct TextAnimationPage: View {
    let onboardingState: OnboardingState

    @State private var visibleLines: Int = 0
    @State private var showFinal = false
    @State private var showFeatures = false
    @State private var canTap = false

    private let textLines: [(text: String, alignment: TextAlignment)] = [
        ("You use ten tools to stay organized.", .leading),
        ("But somehow, nothing gets done.", .leading),
        ("Tasks pile up.", .trailing),
        ("Focus slips away.", .trailing),
        ("And the tools meant to help...", .leading),
        ("...just add more noise.", .leading),
        ("Kirole is different.", .center),
    ]

    private let finalLines = [
        "Turning complexity into action.",
    ]

    private let features: [(emoji: String, text: String)] = [
        ("\u{1F3AF}", "Focus"),
        ("\u{1F30A}", "Flow"),
        ("\u{2705}", "Done"),
    ]

    public init(onboardingState: OnboardingState) {
        self.onboardingState = onboardingState
    }

    public var body: some View {
        ZStack {
            Color(hex: "1A1A2E").ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button {
                        onboardingState.goNext()
                    } label: {
                        Text("Skip")
                            .font(.system(size: 14, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(.white.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                VStack(spacing: 16) {
                    ForEach(Array(textLines.enumerated()), id: \.offset) { index, line in
                        if index < visibleLines {
                            Text(line.text)
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, alignment: alignment(for: line.alignment))
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .offset(y: 20)),
                                    removal: .opacity
                                ))
                        }
                    }

                    if showFinal {
                        ForEach(Array(finalLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(Color(hex: "1A1A2E"))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(.white)
                                .clipShape(Capsule())
                                .transition(.scale.combined(with: .opacity))
                        }
                    }

                    if showFeatures {
                        VStack(spacing: 12) {
                            ForEach(Array(features.enumerated()), id: \.offset) { _, feature in
                                HStack(spacing: 8) {
                                    Text(feature.emoji)
                                        .font(.system(size: 24))
                                    Text(feature.text)
                                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.white)
                                }
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .offset(x: -20)),
                                    removal: .opacity
                                ))
                            }
                        }
                        .padding(.top, 24)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 48)

                Spacer()

                if canTap {
                    Text("(Tap Anywhere To Continue)")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.bottom, 32)
                        .transition(.opacity)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if canTap {
                onboardingState.goNext()
            }
        }
        .task {
            do {
                for i in 1...textLines.count {
                    try await Task.sleep(for: .milliseconds(400))
                    withAnimation(.easeOut(duration: 0.4)) {
                        visibleLines = i
                    }
                }
                try await Task.sleep(for: .milliseconds(300))
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    showFinal = true
                }
                try await Task.sleep(for: .milliseconds(500))
                withAnimation(.easeOut(duration: 0.4)) {
                    showFeatures = true
                }
                try await Task.sleep(for: .milliseconds(700))
                withAnimation(.easeIn(duration: 0.3)) {
                    canTap = true
                }
            } catch {
                // Task cancelled on page transition - expected
            }
        }
    }

    private func alignment(for textAlignment: TextAlignment) -> Alignment {
        switch textAlignment {
        case .leading: return .leading
        case .trailing: return .trailing
        case .center: return .center
        }
    }
}

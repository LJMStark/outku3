import SwiftUI

struct CinematicBackground: View {
    let step: OnboardingStep
    @Environment(ThemeManager.self) private var theme

    @State private var animateGradient = false

    var body: some View {
        ZStack {
            // Base Color
            backgroundColor
                .ignoresSafeArea()

            // Atmospheric Gradients
            if isDarkStep {
                RadialGradient(
                    colors: [.black.opacity(0.0), .black.opacity(0.8)],
                    center: .center,
                    startRadius: 50,
                    endRadius: 400
                )
                .ignoresSafeArea()
                .transition(.opacity)
            }

            // Floating Blobs (Atmosphere)
            if step != .welcome {
                GeometryReader { proxy in
                    Circle()
                        .fill(accentColor.opacity(0.2))
                        .frame(width: 300, height: 300)
                        .blur(radius: 60)
                        .offset(x: animateGradient ? -50 : 50, y: animateGradient ? -50 : 50)
                        .animation(.easeInOut(duration: 10).repeatForever(autoreverses: true), value: animateGradient)
                        .position(x: proxy.size.width * 0.3, y: proxy.size.height * 0.3)

                    Circle()
                        .fill(accentColor.opacity(0.15))
                        .frame(width: 400, height: 400)
                        .blur(radius: 80)
                        .offset(x: animateGradient ? 50 : -50, y: animateGradient ? 50 : -50)
                        .animation(.easeInOut(duration: 15).repeatForever(autoreverses: true), value: animateGradient)
                        .position(x: proxy.size.width * 0.8, y: proxy.size.height * 0.7)
                }
                .ignoresSafeArea()
                .transition(.opacity.animation(.easeInOut(duration: 2.0)))
            }
        }
        .onAppear {
            animateGradient = true
        }
    }

    private var isDarkStep: Bool {
        switch step {
        case .welcome, .identity, .goals, .companionStyle, .awakening, .naming:
            return true
        case .connect, .complete:
            return false
        }
    }

    private var backgroundColor: Color {
        switch step {
        case .welcome:
            return .black
        case .identity, .goals, .companionStyle:
            return Color(hex: "1A1A2E")
        case .awakening, .naming:
            return Color(hex: "0F0F1A")
        case .connect, .complete:
            return theme.colors.background
        }
    }

    private var accentColor: Color {
        switch step {
        case .welcome:
            return .white
        case .identity, .goals, .companionStyle:
            return Color(hex: "6366F1") // Indigo
        case .awakening, .naming:
            return Color(hex: "E94560") // Pink/Red
        case .connect, .complete:
            return theme.colors.accent
        }
    }
}

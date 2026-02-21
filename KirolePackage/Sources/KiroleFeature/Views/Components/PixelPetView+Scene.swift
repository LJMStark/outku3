import SwiftUI

extension PixelPetView {
    @ViewBuilder
    var sceneBackground: some View {
        switch currentScene {
        case .indoor:
            LinearGradient(
                colors: [
                    theme.colors.cardBackground,
                    theme.colors.background
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .overlay(
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.yellow.opacity(0.1),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 100
                        )
                    )
                    .frame(width: 200, height: 150)
                    .offset(x: windowLightX, y: -80)
            )

        case .outdoor:
            LinearGradient(
                colors: [
                    Color(hex: "#87CEEB"),
                    Color(hex: "#E0F7FA")
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .overlay(
                HStack(spacing: 30) {
                    cloudShape
                        .offset(y: -60)
                    cloudShape
                        .scaleEffect(0.7)
                        .offset(y: -40)
                }
                .offset(x: cloudDriftX, y: -20)
            )
            .overlay(
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: "#90EE90"),
                                Color(hex: "#228B22")
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 40)
                    .offset(y: 80)
                , alignment: .bottom
            )

        case .night:
            LinearGradient(
                colors: [
                    Color(hex: "#0D1B2A"),
                    Color(hex: "#1B263B")
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .overlay(
                ZStack {
                    ForEach(0..<8, id: \.self) { index in
                        Circle()
                            .fill(Color.white)
                            .frame(width: starSizes[index], height: starSizes[index])
                            .offset(x: starPositions[index].width, y: starPositions[index].height)
                            .opacity(starTwinkle.indices.contains(index) ? starTwinkle[index] : 0.7)
                    }
                    Circle()
                        .fill(Color(hex: "#F5F5DC"))
                        .frame(width: 30, height: 30)
                        .offset(x: 60, y: -70)
                        .shadow(color: Color(hex: "#F5F5DC").opacity(0.5), radius: 10)
                }
            )

        case .work:
            LinearGradient(
                colors: [
                    theme.colors.background,
                    theme.colors.cardBackground.opacity(0.8)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(
                Circle()
                    .stroke(theme.colors.accent.opacity(0.2), lineWidth: 2)
                    .frame(width: 120, height: 120)
            )
            .overlay(
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle()
                            .fill(theme.colors.accent.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }
                }
                .offset(y: 70)
            )
        }
    }

    var cloudShape: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.9))
                .frame(width: 30, height: 30)
            Circle()
                .fill(Color.white.opacity(0.9))
                .frame(width: 25, height: 25)
                .offset(x: 15, y: 5)
            Circle()
                .fill(Color.white.opacity(0.9))
                .frame(width: 20, height: 20)
                .offset(x: -12, y: 3)
        }
    }

    var shadowColor: Color {
        switch currentScene {
        case .night:
            return Color.white
        default:
            return theme.colors.primaryText
        }
    }

    var petPrimaryColor: Color {
        switch appState.pet.currentForm {
        case .cat:
            return Color(hex: "#FFB366")
        case .dog:
            return Color(hex: "#C4A484")
        case .bunny:
            return Color(hex: "#F5F5DC")
        case .bird:
            return Color(hex: "#87CEEB")
        case .dragon:
            return Color(hex: "#9370DB")
        }
    }

    var petSecondaryColor: Color {
        switch appState.pet.currentForm {
        case .cat:
            return Color(hex: "#FF8C00")
        case .dog:
            return Color(hex: "#8B7355")
        case .bunny:
            return Color(hex: "#FFB6C1")
        case .bird:
            return Color(hex: "#4682B4")
        case .dragon:
            return Color(hex: "#6A5ACD")
        }
    }
}

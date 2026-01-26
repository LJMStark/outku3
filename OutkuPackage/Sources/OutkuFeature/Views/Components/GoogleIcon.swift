import SwiftUI

/// Shared Google icon component with the characteristic multi-color arc
/// Used in both onboarding sign-in and settings integrations
struct GoogleIcon: View {
    /// Line width for the arc stroke (default: 2.5)
    var lineWidth: CGFloat = 2.5
    /// Inset from the edge (default: 2.5)
    var inset: CGFloat = 2.5

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white)

            GeometryReader { geo in
                Path { path in
                    let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                    let radius = min(geo.size.width, geo.size.height) / 2 - inset

                    path.addArc(
                        center: center,
                        radius: radius,
                        startAngle: .degrees(-45),
                        endAngle: .degrees(270),
                        clockwise: false
                    )
                }
                .stroke(
                    AngularGradient(
                        colors: [
                            Color(hex: "4285F4"),  // Google Blue
                            Color(hex: "34A853"),  // Google Green
                            Color(hex: "FBBC05"),  // Google Yellow
                            Color(hex: "EA4335"),  // Google Red
                            Color(hex: "4285F4")   // Back to Blue
                        ],
                        center: .center
                    ),
                    lineWidth: lineWidth
                )
            }
        }
    }
}

#Preview {
    HStack(spacing: 20) {
        GoogleIcon()
            .frame(width: 20, height: 20)

        GoogleIcon(lineWidth: 3, inset: 3)
            .frame(width: 32, height: 32)

        GoogleIcon(lineWidth: 4, inset: 4)
            .frame(width: 48, height: 48)
    }
    .padding()
    .background(Color.gray.opacity(0.2))
}

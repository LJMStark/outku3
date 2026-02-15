import SwiftUI

public struct FloatingIconRing: View {
    private let icons: [(symbol: String, color: Color, delay: Double)] = [
        ("calendar", Color(hex: "4285F4"), 0),
        ("checkmark.square.fill", Color(hex: "EA4335"), 0.2),
        ("clock.fill", Color(hex: "FBBC05"), 0.4),
        ("envelope.fill", Color(hex: "34A853"), 0.6),
        ("list.bullet", Color(hex: "5B5FC7"), 0.8),
        ("calendar.day.timeline.left", Color(hex: "FF6B6B"), 1.0),
    ]

    @State private var rotation: Double = 0

    public init() {}

    public var body: some View {
        ZStack {
            ForEach(Array(icons.enumerated()), id: \.offset) { index, icon in
                let angle = Double(index) * 60.0 * .pi / 180.0
                let radius: CGFloat = 120

                IconBubble(symbol: icon.symbol, color: icon.color, bobDelay: icon.delay)
                    .offset(
                        x: cos(angle + rotation * .pi / 180) * radius,
                        y: sin(angle + rotation * .pi / 180) * radius
                    )
            }
        }
        .frame(width: 288, height: 288)
        .onAppear {
            withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

private struct IconBubble: View {
    let symbol: String
    let color: Color
    let bobDelay: Double

    @State private var bobOffset: CGFloat = 0

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(color)
                .frame(width: 40, height: 40)
                .shadow(color: color.opacity(0.4), radius: 8, y: 4)

            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
        }
        .offset(y: bobOffset)
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true).delay(bobDelay)) {
                bobOffset = -10
            }
        }
    }
}

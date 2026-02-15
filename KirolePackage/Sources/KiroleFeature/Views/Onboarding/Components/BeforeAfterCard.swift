import SwiftUI

public struct BeforeAfterCard: View {
    @State private var showAfter = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showAfter.toggle()
                }
            } label: {
                ZStack {
                    if !showAfter {
                        beforeContent
                            .transition(.opacity)
                    } else {
                        afterContent
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
            }
            .buttonStyle(.plain)

            Text("Tap card to see the difference")
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.top, 16)
        }
    }

    private var beforeContent: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                ForEach(0..<8, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: "E5E7EB"))
                        .frame(height: 12)
                        .frame(maxWidth: .infinity)
                        .blur(radius: 2)
                }
            }
            Text("HEEEELP!")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.red)
                .clipShape(Capsule())
                .rotationEffect(.degrees(-6))

            Text("BEFORE")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .background(Color.red)
                .clipShape(Capsule())
        }
        .padding(24)
    }

    private var afterContent: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(hex: "0D8A6A"))
                        .frame(width: 40, height: 40)
                    Text("factory")
                        .font(.system(size: 10))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("2:30 Inku Factory Sync")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "1A1A2E"))

                    Text("With: You, Britt and 3 others.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(hex: "4B5563"))

                    Text("Meeting with Raymond at the factory. Call to discuss next steps in production.")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(Color(hex: "6B7280"))
                        .lineLimit(3)
                }
            }
            .padding(16)
            .background(Color(hex: "F5F5F0"))
            .clipShape(RoundedRectangle(cornerRadius: 16))

            Text("AFTER")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .background(Color(hex: "0D8A6A"))
                .clipShape(Capsule())
        }
        .padding(24)
    }
}

import SwiftUI

// MARK: - Event Card View

struct EventCardView: View {
    let title: String
    let duration: String
    let participants: Int
    let description: String
    var onTap: (() -> Void)? = nil

    @Environment(ThemeManager.self) private var theme
    @State private var isPressed = false

    var body: some View {
        Button {
            onTap?()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                // Title
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(theme.colors.primaryText)
                    .multilineTextAlignment(.leading)

                // Meta info
                HStack(spacing: 12) {
                    Text(duration)
                        .font(.system(size: 14))
                        .foregroundStyle(theme.colors.secondaryText)

                    HStack(spacing: 4) {
                        Text("👥")
                            .font(.system(size: 12))
                        Text("\(participants)")
                            .font(.system(size: 14))
                            .foregroundStyle(theme.colors.secondaryText)
                    }
                }

                // Description
                Text(description)
                    .font(.system(size: 14))
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(hex: "E5E7EB"), lineWidth: 1)
            )
        }
        .buttonStyle(CardButtonStyle())
    }
}

// MARK: - Card Button Style

private struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .shadow(
                color: .black.opacity(configuration.isPressed ? 0.12 : 0.08),
                radius: configuration.isPressed ? 4 : 8,
                y: configuration.isPressed ? 2 : 4
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Event Detail Modal

public struct EventDetailModal: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var theme

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Text("Open In")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.colors.secondaryText)

                    HStack(spacing: 6) {
                        GoogleIconView()
                            .frame(width: 16, height: 16)

                        Text("#393837262@gmail.com")
                            .font(.system(size: 14))
                            .foregroundStyle(theme.colors.primaryText)

                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.colors.secondaryText)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(theme.colors.primaryText)
                        .frame(width: 36, height: 36)
                        .background(Color.white)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 24)

            // Event Title Card
            EventDetailCard {
                HStack(alignment: .top) {
                    Image(systemName: "calendar")
                        .font(.system(size: 18))
                        .foregroundStyle(theme.colors.secondaryText)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Factory tour")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(theme.colors.primaryText)

                            Spacer()

                            Button {
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.system(size: 14))
                                    .foregroundStyle(theme.colors.secondaryText)
                            }
                        }

                        Text("with teammates to discuss details of product\ndemon for tiko calendar")
                            .font(.system(size: 14))
                            .foregroundStyle(theme.colors.secondaryText)
                            .lineSpacing(4)

                        Text("Tap to expand")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.colors.secondaryText.opacity(0.6))
                            .padding(.top, 4)
                    }
                }
            }

            // Time Card
            EventDetailCard {
                HStack(alignment: .top) {
                    Image(systemName: "clock")
                        .font(.system(size: 18))
                        .foregroundStyle(theme.colors.secondaryText)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Friday, Jan 9 · 2:00 PM-3:00 PM · 1h")
                                .font(.system(size: 14))
                                .foregroundStyle(theme.colors.primaryText)

                            Spacer()

                            Button {
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.system(size: 14))
                                    .foregroundStyle(theme.colors.secondaryText)
                            }
                        }

                        HStack(spacing: 8) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14))
                                .foregroundStyle(theme.colors.secondaryText)

                            Text("Starts in 18h")
                                .font(.system(size: 14))
                                .foregroundStyle(theme.colors.secondaryText)
                        }
                    }
                }
            }

            // Repeat Card
            EventDetailCard {
                HStack {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 18))
                        .foregroundStyle(theme.colors.secondaryText)

                    Text("Does not repeat")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.colors.primaryText)

                    Spacer()

                    Button {
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 14))
                            .foregroundStyle(theme.colors.secondaryText)
                    }
                }
            }

            // Email Card
            EventDetailCard {
                HStack {
                    Image(systemName: "person")
                        .font(.system(size: 18))
                        .foregroundStyle(theme.colors.secondaryText)

                    Text("#393837262@gmail.com")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.colors.primaryText)

                    Spacer()
                }
            }

            Spacer()
        }
        .background(Color(hex: "e8e4e0"))
    }
}

// MARK: - Event Detail Card

private struct EventDetailCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
    }
}

// MARK: - Google Icon View

private struct GoogleIconView: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white)

            // Simplified Google G
            GeometryReader { geo in
                Path { path in
                    let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                    let radius = min(geo.size.width, geo.size.height) / 2 - 2

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
                            Color(hex: "4285F4"),
                            Color(hex: "34A853"),
                            Color(hex: "FBBC05"),
                            Color(hex: "EA4335"),
                            Color(hex: "4285F4")
                        ],
                        center: .center
                    ),
                    lineWidth: 2
                )
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        EventCardView(
            title: "New Product Factory Tour!",
            duration: "1h",
            participants: 2,
            description: "Join your coworkers for a factory tour in Shenzhen to see how the new product is made. Exciting!"
        )
        .padding(.horizontal, 24)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(hex: "f5f1e8"))
    .environment(ThemeManager.shared)
}

#Preview("Event Detail Modal") {
    EventDetailModal()
        .environment(ThemeManager.shared)
}

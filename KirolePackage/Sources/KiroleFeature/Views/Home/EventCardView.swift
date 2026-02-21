import SwiftUI

// MARK: - Event Card View

struct EventCardView: View {
    let title: String
    let duration: String
    let participants: Int
    let description: String
    let source: EventSource
    var onTap: (() -> Void)? = nil

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        Button {
            onTap?()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                // Title
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color(hex: "294A3B"))
                    .multilineTextAlignment(.leading)

                // Meta info
                HStack(spacing: 10) {
                    Text(duration)
                        .font(.system(size: 14))
                        .foregroundStyle(theme.colors.secondaryText)

                    EventSourceIconView(source: source, size: 16)

                    HStack(spacing: 4) {
                        Image(systemName: "person.2")
                            .font(.system(size: 14))
                            .foregroundStyle(theme.colors.secondaryText)
                        Text("\(participants)")
                            .font(.system(size: 14))
                            .foregroundStyle(theme.colors.secondaryText)
                    }
                }
                .padding(.vertical, 4)

                // Description
                Text(description)
                    .font(.system(size: 16))
                    .foregroundStyle(Color(hex: "294A3B"))
                    .lineSpacing(4)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(hex: "294A3B"), lineWidth: 1)
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
            .animation(Animation.appStandard, value: configuration.isPressed)
    }
}

// MARK: - Event Detail Formatters

private enum EventDetailFormatters {
    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    static let date: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter
    }()
}

// MARK: - Event Detail Modal

public struct EventDetailModal: View {
    let event: CalendarEvent
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var theme

    public init(event: CalendarEvent) {
        self.event = event
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            Capsule()
                .fill(Color(hex: "D1D5DB"))
                .frame(width: 40, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 8)

            // Header
            HStack {
                HStack(spacing: 6) {
                    Text("Open In")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.colors.primaryText)

                    EventSourceIconView(source: event.source, size: 14)

                    Text(event.source.rawValue)
                        .font(.system(size: 14))
                        .foregroundStyle(theme.colors.primaryText)
                        .lineLimit(1)

                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.colors.secondaryText)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.colors.primaryText)
                        .frame(width: 30, height: 30)
                        .background(Color.white)
                        .clipShape(Circle())
                        .overlay(
                            Circle().stroke(Color(hex: "E5E7EB"), lineWidth: 1)
                        )
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // Event Title Card
                    EventDetailCard {
                        VStack(spacing: 0) {
                            EventDetailRow(icon: "calendar", showPencil: true) {
                                Text(event.title.isEmpty ? "No Title" : event.title)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(theme.colors.primaryText)
                            }
                            if let desc = event.description, !desc.isEmpty {
                                Divider().padding(.leading, 48)
                                EventDetailRow(icon: "text.alignleft", showPencil: false) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(desc)
                                            .font(.system(size: 14))
                                            .foregroundStyle(theme.colors.primaryText)
                                            .lineSpacing(2)
                                        Text("Tap to expand")
                                            .font(.system(size: 12))
                                            .foregroundStyle(theme.colors.secondaryText.opacity(0.8))
                                    }
                                }
                            }
                        }
                    }

                    // Time Card
                    EventDetailCard {
                        VStack(spacing: 0) {
                            EventDetailRow(icon: "calendar.badge.clock", showPencil: true) {
                                Text("\(EventDetailFormatters.date.string(from: event.startTime)) · \(EventDetailFormatters.time.string(from: event.startTime))-\(EventDetailFormatters.time.string(from: event.endTime)) · \(event.durationText)")
                                    .font(.system(size: 14))
                                    .foregroundStyle(theme.colors.primaryText)
                            }
                            Divider().padding(.leading, 48)
                            EventDetailRow(icon: "arrow.left.arrow.right", showPencil: false) {
                                Text(startStatusText())
                                    .font(.system(size: 14))
                                    .foregroundStyle(theme.colors.primaryText)
                            }
                        }
                    }

                    // Repeat Card
                    EventDetailCard {
                        EventDetailRow(icon: "arrow.2.squarepath", showPencil: true) {
                            Text("Does not repeat")
                                .font(.system(size: 14))
                                .foregroundStyle(theme.colors.primaryText)
                        }
                    }

                    // Email Card
                    if !event.participants.isEmpty {
                        EventDetailCard {
                            VStack(spacing: 0) {
                                ForEach(Array(event.participants.enumerated()), id: \.element.id) { index, participant in
                                    EventDetailRow(icon: "person", showPencil: false) {
                                        Text(participant.name)
                                            .font(.system(size: 14))
                                            .foregroundStyle(theme.colors.primaryText)
                                    }
                                    if index < event.participants.count - 1 {
                                        Divider().padding(.leading, 48)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 32)
            }
        }
        .background(Color.white)
    }

    private func startStatusText() -> String {
        let diff = event.startTime.timeIntervalSinceNow
        if diff <= 0 {
            return "Started"
        }
        let hours = Int(diff) / 3600
        if hours > 0 {
            return "Starts in \(hours)h"
        }
        let mins = max(1, Int(diff) / 60)
        return "Starts in \(mins)m"
    }
}

// MARK: - Event Detail Card

private struct EventDetailCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(hex: "E5E7EB"), lineWidth: 1)
            )
            .padding(.horizontal, 20)
    }
}

// MARK: - Event Detail Row

private struct EventDetailRow<Content: View>: View {
    let icon: String // systemName
    let showPencil: Bool
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.black.opacity(0.6))
                .frame(width: 24, alignment: .center)
                .padding(.top, 2)

            HStack(alignment: .top) {
                content
                Spacer(minLength: 16)
                if showPencil {
                    Button {
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.black.opacity(0.4))
                    }
                }
            }
        }
        .padding(16)
    }
}

// MARK: - Google Icon View

private struct EventSourceIconView: View {
    let source: EventSource
    let size: CGFloat

    var body: some View {
        Group {
            switch source {
            case .google:
                GoogleIconView()
            case .apple:
                Image(systemName: "apple.logo")
                    .font(.system(size: size * 0.85))
                    .foregroundStyle(Color.black.opacity(0.75))
            case .todoist:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: size * 0.95))
                    .foregroundStyle(Color(hex: "DC4C3E"))
            }
        }
        .frame(width: size, height: size)
    }
}

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
            description: "Join your coworkers for a factory tour in Shenzhen to see how the new product is made. Exciting!",
            source: .google
        )
        .padding(.horizontal, 24)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(hex: "f5f1e8"))
    .environment(ThemeManager.shared)
}

#Preview("Event Detail Modal") {
    EventDetailModal(event: CalendarEvent(
        title: "Factory tour",
        startTime: Date(),
        endTime: Date().addingTimeInterval(3600),
        source: .google,
        participants: [
            Participant(name: "Alex Chen"),
            Participant(name: "Sarah Kim")
        ],
        description: "with teammates to discuss details of product demon for tiko calendar"
    ))
        .environment(ThemeManager.shared)
}

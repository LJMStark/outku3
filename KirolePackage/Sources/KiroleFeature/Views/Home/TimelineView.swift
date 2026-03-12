import SwiftUI

// MARK: - Date Divider View

struct DateDividerView: View {
    let date: Date
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        HStack(spacing: 16) {
            Rectangle()
                .fill(theme.colors.accent)
                .frame(height: 4)
                .clipShape(Capsule())

            Text(formattedDate)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(theme.colors.accent)

            Rectangle()
                .fill(theme.colors.accent)
                .frame(height: 4)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 24)
    }

    private var formattedDate: String {
        AppDateFormatters.separatorDate.string(from: date)
    }
}

// MARK: - Day Timeline View

struct DayTimelineView: View {
    let date: Date
    let events: [CalendarEvent]
    var showPet: Bool = false

    @Environment(ThemeManager.self) private var theme

    private var sunTimes: SunTimes { .forDate(date) }

    /// Insert pet after this many events (0-indexed boundary).
    private let petInsertAfter = 2

    var body: some View {
        VStack(spacing: 0) {
            TimelineEventRow(
                time: AppDateFormatters.time.string(from: sunTimes.sunrise),
                icon: "sunrise.fill",
                title: "Sunrise",
                delay: 0,
                isSystemIcon: true
            )

            TimelineEventRow(
                time: "9:00 AM",
                icon: "sun.max.fill",
                title: "Day Start",
                delay: 0,
                isSystemIcon: true
            )

            if events.isEmpty {
                TimelineEmptyStateRow(delay: 0)

                if showPet {
                    HaikuSectionView(delay: 0)
                }
            } else {
                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    TimelineEventCardRow(event: event, delay: 0)

                    if showPet && index == min(petInsertAfter - 1, events.count - 1) {
                        HaikuSectionView(delay: 0)
                    }
                }
            }

            TimelineEventRow(
                time: AppDateFormatters.time.string(from: sunTimes.sunset),
                icon: "sunset.fill",
                title: "Sunset",
                delay: 0,
                isSystemIcon: true
            )
        }
        .background(
            // Vertical timeline line
            HStack {
                Spacer()
                    .frame(width: 64)
                Rectangle()
                    .fill(Color(hex: "D1D5DB"))
                    .frame(width: 2)
                Spacer()
            }
        )
    }
}

// MARK: - Timeline Empty State Row

struct TimelineEmptyStateRow: View {
    let delay: Double

    @Environment(ThemeManager.self) private var theme
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 0) {
            Spacer()
                .frame(width: 80)

            VStack(spacing: 8) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 32))
                    .foregroundStyle(theme.colors.secondaryText.opacity(0.5))

                Text("No events today")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.colors.secondaryText)

                Text("Connect your calendar to see events")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.colors.secondaryText.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
        .animation(.easeOut(duration: 0.5).delay(delay), value: appeared)
        .onAppear {
            appeared = true
        }
    }
}

// MARK: - Timeline Event Card Row

struct TimelineEventCardRow: View {
    let event: CalendarEvent
    let delay: Double

    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Time header
            HStack {
                Text(AppDateFormatters.time.string(from: event.startTime))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.colors.secondaryText)
                    .frame(width: 64, alignment: .leading)

                Spacer()
            }
            .padding(.top, 8)

            // Event card
            HStack(spacing: 0) {
                Spacer()
                    .frame(width: 80)

                EventCardView(
                    title: event.title,
                    duration: event.durationText,
                    participants: event.participants.count,
                    description: event.description ?? "",
                    source: event.source,
                    onTap: {
                        appState.selectEvent(event)
                    }
                )
            }
            .padding(.vertical, 8)
        }
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : -30)
        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(delay), value: appeared)
        .onAppear {
            appeared = true
        }
    }
}

// MARK: - Timeline Event Row

struct TimelineEventRow: View {
    let time: String
    let icon: String
    let title: String
    let delay: Double
    var isSystemIcon: Bool = false

    @Environment(ThemeManager.self) private var theme
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 16) {
            // Time
            Text(time)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.colors.secondaryText)
                .frame(width: 64, alignment: .leading)

            // Icon circle
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: 32, height: 32)
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)

                if isSystemIcon {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundStyle(theme.colors.accent)
                } else {
                    Text(icon)
                        .font(.system(size: 18))
                }
            }

            // Title
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.colors.primaryText)

            Spacer()
        }
        .padding(.vertical, 16)
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : -30)
        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(delay), value: appeared)
        .onAppear {
            appeared = true
        }
    }
}

// MARK: - Haiku Section View

struct HaikuSectionView: View {
    let delay: Double

    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var appeared = false
    @State private var ballOffset: CGFloat = -140
    @State private var ballRotation: Double = -180

    var body: some View {
        HStack(spacing: 0) {
            Spacer()
                .frame(width: 80)

            VStack(spacing: 24) {
                // Haiku text from AppState
                VStack(spacing: 4) {
                    ForEach(Array(appState.currentHaiku.lines.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.system(size: 15, weight: .regular, design: .serif))
                            .italic()
                            .foregroundStyle(theme.colors.primaryText)
                    }
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

                // Pet image with rolling toy ball
                ZStack {
                    PetToyBall(size: 46)
                        .rotationEffect(.degrees(ballRotation))
                        // The pet image has height 200.
                        // Setting y to 25 brings the ball up tighter to the pet's sitting baseline
                        .offset(x: ballOffset, y: 25)

                    Image("tiko_reading", bundle: .module)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                }
            }
            .padding(.vertical, 24)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
        .animation(.easeOut(duration: 0.6).delay(delay), value: appeared)
        .onAppear {
            appeared = true
            
            // Rolling Ball Animation
            withAnimation(
                .easeInOut(duration: 4.0)
                .repeatForever(autoreverses: true)
            ) {
                ballOffset = 140
                ballRotation = 360 * 2.5
            }
        }
    }
}

// MARK: - Pet Toy Ball

private struct PetToyBall: View {
    let size: CGFloat
    
    var body: some View {
        ZStack {
            // Base sphere with 3D shading
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [Color(hex: "E0C9B1"), Color(hex: "AE917A")]),
                        center: UnitPoint(x: 0.3, y: 0.3),
                        startRadius: 0,
                        endRadius: size * 0.8
                    )
                )
            
            // Subtle top-left highlight
            Capsule()
                .fill(Color.white.opacity(0.35))
                .frame(width: size * 0.35, height: size * 0.18)
                .rotationEffect(.degrees(-30))
                .offset(x: -size * 0.18, y: -size * 0.22)
            
            // Elegant horizontal stripe (curved for 3D sphere look)
            Ellipse()
                .stroke(Color(hex: "F2E2CF"), lineWidth: size * 0.1)
                .frame(width: size * 1.5, height: size * 0.6)
                .offset(y: size * 0.12)
                
            // Inner bottom shadow for extra depth
            Circle()
                .stroke(Color(hex: "816752").opacity(0.2), lineWidth: size * 0.12)
                .offset(x: size * 0.05, y: size * 0.05)
                .blur(radius: size * 0.03)
        }
        .clipShape(Circle()) // Ensures contents stay within the sphere
        .frame(width: size, height: size)
        .shadow(color: Color(hex: "A38771").opacity(0.4), radius: size * 0.12, x: 0, y: size * 0.08)
    }
}

#Preview {
    ScrollView {
        DayTimelineView(date: Date(), events: [])
            .padding(.horizontal, 24)
    }
    .background(Color(hex: "f5f1e8"))
    .environment(AppState.shared)
    .environment(ThemeManager.shared)
}
